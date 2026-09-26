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
New installations add one explicit call inside the Rails configure block:

```ruby
# app-url-rails: configuration v1
AppUrl.configure_development!(config)
```

The marker identifies the installation format, so gem releases can improve the
implementation without replacing application-owned configuration.

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
| `AppUrl.public_base_url` | Normalized tunnel origin (no trailing slash/default port), otherwise `AppUrl.base_url` |
| `AppUrl.public_url` | Validated `TUNNEL_URL` with its original spelling, or `nil` |
| `AppUrl.configure_development!(config)` | Validates both environment URLs and applies host, route-default, and Cable wiring |

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
installing the gem. Both values are validated before any Rails configuration is
changed. When `DEV_URL` is set, the setup updates only the host, protocol, and
effective port in `Rails.application.default_url_options`, preserving unrelated
options. A default port also clears a stale non-default `:port`. Existing hosts
and Action Cable origins remain in place.
The call overrides earlier address defaults when `DEV_URL` is set; explicit
configuration written after the call takes precedence over its results.

The setup call is explicit and has no environment gate: it works in any Rails
environment where the application calls it, while the generator installs it in
development only. Requiring the gem alone does not configure an application;
the gem has no Railtie or automatic hook.

Configure the default explicitly in each environment that needs URLs outside
an incoming request, for example:

```ruby
# config/environments/production.rb, inside Rails.application.configure
Rails.application.default_url_options = { host: "example.com", protocol: "https" }
```

`AppUrl` does not infer the host from the current request or read
`config.action_mailer.default_url_options`. Without a configured host,
`AppUrl.host` and `AppUrl.base_url` return `nil`.

Put the call in the environment's `Rails.application.configure` block, before
Rails builds host authorization middleware and applies Action Cable configuration:

```ruby
# config/environments/development.rb
Rails.application.configure do
  # app-url-rails: configuration v1
  AppUrl.configure_development!(config)
end
```

An appropriately ordered initializer can run before middleware construction;
`config.after_initialize` is too late for host wiring. Calling from the
environment configure block is the supported timing.

## Development tunnels

`AppUrl` reads `TUNNEL_URL` from the environment each time a public helper is
called. Any tunnel provider works: ngrok, Cloudflare Tunnel, Tailscale Funnel,
a custom reverse proxy.

Use absolute HTTP(S) URLs with a host, an optional port from 1 through 65535,
and an optional trailing slash, such as `http://localhost:3000` and
`https://example.ngrok-free.app`. Scheme-less values, missing hosts,
unsupported schemes, userinfo, non-root paths, queries, fragments, invalid
ports, and whitespace-only values raise
`AppUrl::ConfigurationError < ArgumentError`. Setup validates both values when
called. Public helpers validate `TUNNEL_URL` independently in every environment.
Errors name the setting and failure without echoing unsafe raw input. Unset or
empty values mean no override.
Restart Rails after changing these environment variables so boot-time host and
Action Cable configuration are refreshed; public helpers still read
`TUNNEL_URL` on demand.

For parallel-worktree workflows such as
[git-treeline](https://github.com/git-treeline/git-treeline), each workspace
can export its own `DEV_URL` and `TUNNEL_URL`, giving every branch distinct
internal and public URLs without manual `.env` edits.

See [git-treeline and AppUrl Adoption](docs/git-treeline.md) for setup patterns
with and without git-treeline, the Rails stack touchpoints `AppUrl` can feed,
and the Action Cable port nuance for router-backed development URLs.

## How it works

The install generator adds the marked setup call shown above. The gem owns the
parsing and Rails wiring behind that call, including `config.hosts`,
`Rails.application.default_url_options`, and Action Cable origins. It preserves
existing allowlists and unrelated URL options, and repeated calls do not add
duplicates. The public helpers read `TUNNEL_URL` on demand, but boot-time host
and Action Cable wiring requires a restart after environment changes.

`AppUrl.base_url` delegates protocol and origin construction to Rails. An
omitted protocol follows Rails' effective default, including HTTPS when
`force_ssl` is enabled. Configured protocol spellings follow Rails, including
`http`, `https`, `http:`, and `https://`. Explicit empty protocols and malformed
values such as `http::` raise `ArgumentError` rather than being repaired.
`url_options` remains a passthrough to the application's defaults.

Every public helper validates `TUNNEL_URL` when called. `AppUrl.public_url`
returns the original valid string or `nil` when no override is set; it does not
fall back to another URL. The other public helpers retain their documented
fallback behavior when the override is absent.
With an override, `public_url_options` includes its effective port, even 80 or
443, so Rails route helpers cannot inherit a different application port.

## Upgrading from 1.x

Version 2.0 changes these contracts:

- Host-only `base_url` follows Rails' effective protocol instead of always using
  HTTPS. Set `protocol: "https"` explicitly when that is your intended address.
- Empty and malformed configured protocols such as `http::` raise Rails'
  `ArgumentError`; the gem no longer repairs them.
- Invalid environment addresses raise `AppUrl::ConfigurationError`, including
  through `public_url`. Path prefixes and other unsupported components are rejected.
- `public_base_url` normalizes trailing slashes and default ports; use
  `public_url` for the valid input's original spelling.
- `public_url_options` includes the tunnel's effective port, preventing route
  helpers from inheriting the development application's port.
- Supported Rails lines are now 8.0 and 8.1, replacing the unverified 7.0+ claim.

The 2.0 installer does not rewrite copied application code. For a one-time
manual migration, open `config/environments/development.rb` and remove only the
complete old generated wiring: its helper plus the `DEV_URL` and `TUNNEL_URL`
branches. Preserve custom configuration around it. Add the supported call and
marker in the configure block:

```ruby
# app-url-rails: configuration v1
AppUrl.configure_development!(config)
```

Boot the app and verify its development URLs. If the old block is partial,
customized, ambiguous, or conflicts with the marker, resolve it manually; the
installer exits non-zero with an actionable diagnostic and leaves the file
unchanged. A recognized v1 installation is a verified no-op. Once migrated,
future gem upgrades use the existing call and do not replace it.

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

AppUrl 2.0 is a breaking release targeting:

- Ruby >= 3.2 (tested on Ruby 3.2 and 3.4)
- Rails 8.0 and 8.1 (per-line Gemfiles in `gemfiles/`)

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/productmatter/app-url-rails). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventions.

## License

Released under the [Apache 2.0 License](LICENSE.txt).
