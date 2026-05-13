# app-url-rails

[![Gem Version](https://img.shields.io/gem/v/app-url-rails.svg)](https://rubygems.org/gems/app-url-rails)
[![CI](https://github.com/productmatter/app-url-rails/actions/workflows/main.yml/badge.svg)](https://github.com/productmatter/app-url-rails/actions/workflows/main.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE.txt)

A single API for resolving your Rails app's URL across production, development,
and tunneled environments. Replaces ad-hoc `request.host`,
`default_url_options`, and `ENV` lookups with one consistent call.

## Installation

Add the gem and run the install generator:

```sh
bundle add app-url-rails
bin/rails g app_url:install
```

The generator is idempotent and modifies only `config/environments/development.rb`.

## Usage

```ruby
# Internal URLs: app's configured host
redirect_to dashboard_url(**AppUrl.url_options)

# Public URLs: TUNNEL_URL when set, otherwise the configured host
WebhookClient.register(callback_url: order_callback_url(**AppUrl.public_url_options))
```

## API

| Method | Returns |
| --- | --- |
| `AppUrl.host` | Configured host (`default_url_options[:host]`) |
| `AppUrl.url_options` | Full `default_url_options` hash |
| `AppUrl.base_url` | Scheme + host + port, e.g. `"https://example.com"` |
| `AppUrl.public_host` | `TUNNEL_URL` host when set, otherwise `AppUrl.host` |
| `AppUrl.public_url_options` | Options hash derived from `TUNNEL_URL`, otherwise `AppUrl.url_options` |
| `AppUrl.public_base_url` | `TUNNEL_URL` when set, otherwise `AppUrl.base_url` |
| `AppUrl.public_url` | Raw `TUNNEL_URL` value, or `nil` |

Use the unprefixed methods for internal-facing links (admin pages, in-app
redirects). Use `public_*` for anything an external system must reach: webhook
callbacks, SMS links, OAuth redirects, partner API responses.

## Configuration

Two environment variables, both optional, both conventionally development-only:

| Variable | Purpose |
| --- | --- |
| `DEV_URL` | Browser-facing URL for development. Sets `default_url_options` and adds the host to `config.hosts`. |
| `TUNNEL_URL` | Publicly reachable URL for development. Surfaces via `AppUrl.public_*` and is added to `config.hosts`. |

With neither set, the development environment behaves as it did before
installing the gem. In production, both are typically unset and `AppUrl`
resolves entirely from `Rails.application.default_url_options`.

## Development tunnels

`AppUrl` reads `TUNNEL_URL` from the environment at request time. Any tunnel
provider works: ngrok, Cloudflare Tunnel, Tailscale Funnel, a custom reverse
proxy.

For parallel-worktree workflows such as
[git-treeline](https://github.com/git-treeline/git-treeline), each workspace
can export its own `DEV_URL` and `TUNNEL_URL`, giving every branch distinct
internal and public URLs without manual `.env` edits.

## How it works

The install generator inserts the following block inside
`Rails.application.configure` in `config/environments/development.rb`:

```ruby
# app-url-rails: dev URL + tunnel URL wiring.
require "uri"

if (dev = ENV["DEV_URL"]) && !dev.empty?
  uri = URI(dev)
  config.hosts << uri.host
  opts = { host: uri.host, protocol: uri.scheme }
  opts[:port] = uri.port unless uri.port == uri.default_port
  Rails.application.default_url_options = opts
end

if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
  config.hosts << URI(tunnel).host
end
```

The wiring must execute during configuration, not in an initializer or
`config.after_initialize`. `ActionDispatch::HostAuthorization` snapshots
`config.hosts` during `Rails.application.initialize!`; entries added later are
silently ignored.

The gem itself ships no Railtie and runs no boot-time code. The class reads
`Rails.application.default_url_options` and `ENV["TUNNEL_URL"]` on demand.
Hand-wiring the env vars or host config is equally supported.

## Known limitations

### Session cookies on Public Suffix List hosts

Many tunnel providers serve apps on domains listed in the
[Public Suffix List](https://publicsuffix.org/): `ngrok-free.app`,
`herokuapp.com`, `vercel.app`, and others.

Rails' `session_store :cookie_store, domain: :all` derives the `Domain=`
attribute from the public suffix. Browsers reject `Set-Cookie` responses
whose `Domain=` is itself a public suffix, causing the session cookie to be
silently dropped — typically surfacing as a sign-in redirect loop.

Use host-only cookies in development:

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: "_yourapp_session",
  domain: (Rails.env.production? ? ENV["SESSION_COOKIE_DOMAIN"].presence : nil)
```

## Requirements

- Ruby >= 3.2
- Rails 7.0+

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/productmatter/app-url-rails). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventions.

## License

Released under the [Apache 2.0 License](LICENSE.txt).
