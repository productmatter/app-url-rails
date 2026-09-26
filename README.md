# app-url-rails

[![GitHub Release](https://img.shields.io/github/v/release/productmatter/app-url-rails)](https://github.com/productmatter/app-url-rails/releases)
[![CI](https://github.com/productmatter/app-url-rails/actions/workflows/main.yml/badge.svg)](https://github.com/productmatter/app-url-rails/actions/workflows/main.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE.txt)

**The right Rails URL for every worktree.**

Run parallel copies of your app for different branches, developers, or AI
agents. Your workspace tooling supplies each instance's address. AppUrl connects
it to Rails' URL defaults, allowed hosts, and Action Cable, and gives your code
one API for application URLs and public callbacks.

Born alongside [git-treeline](docs/git-treeline.md), AppUrl works with any tool
that supplies environment variables before Rails starts: a workspace manager,
shell script, or container launcher. Install once; each instance uses the
addresses its environment supplies.

Try the [Rails example](examples/worktree_app/README.md) to see the local
gem, install generator, Treeline URL allocation, and Action Cable work together.

## Installation

Install from the GitHub release tag by adding this to your Gemfile:

```ruby
gem "app-url-rails", git: "https://github.com/productmatter/app-url-rails.git", tag: "v2.0.0"
```

The Git tag works with Bundler without a RubyGems publication. Keep the gem
available in every environment where application code calls `AppUrl`.
Then install dependencies and run the generator once:

```sh
bundle install
bin/rails g app_url:install
```

Have your tooling supply these before server startup, or export them yourself
using addresses provided by your local server/router and tunnel:

```sh
export DEV_URL=https://checkout-fix.localhost
export TUNNEL_URL=https://checkout-fix.ngrok.app # optional
```

AppUrl handles the Rails wiring. Your tooling handles the server, routing, and
tunnel. The generator changes only `config/environments/development.rb`.
Existing 1.x users: follow the [one-time upgrade](#upgrading-from-1x).

## Usage

```ruby
AppUrl.base_url         # => "https://checkout-fix.localhost"
AppUrl.public_base_url  # => "https://checkout-fix.ngrok.app"
```

Without `TUNNEL_URL`, `public_base_url` falls back to the app's address. Use the
options helpers when generating named Rails routes:

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
When Cable origins are unset in development, setup preserves Rails' default
localhost allowance. An explicit empty or custom origin list keeps its policy;
setup adds only the configured development/tunnel origins to that list.
The call overrides earlier address defaults when `DEV_URL` is set; explicit
configuration written after the call takes precedence over its results.

The setup call is explicit and has no environment gate: it works in any Rails
environment where the application calls it, while the generator installs it in
development only. Requiring the gem alone does not configure an application;
the gem has no Railtie or automatic hook.

The runtime URL helpers are supported in development, test, and production,
independently of the setup call. Production applications own their Rails URL
defaults and normally leave `DEV_URL` and `TUNNEL_URL` unset. Without a tunnel,
`public_host`, `public_url_options`, and `public_base_url` use those defaults;
`public_url` returns `nil`. A configured `TUNNEL_URL` overrides the public
helpers in every environment, so set it in production only deliberately.
OAuth callback configuration and webhook validation remain application-owned.

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

See [git-treeline and AppUrl Adoption](docs/git-treeline.md) for setup patterns
with and without git-treeline, the Rails stack touchpoints `AppUrl` can feed,
and the Action Cable port nuance for router-backed development URLs.

## How it works

The install generator adds an explicit setup call inside the development
configure block:

```ruby
# app-url-rails: configuration v1
AppUrl.configure_development!(config)
```

The marker identifies the installation format, independently of the gem version.
A recognized installation is an unchanged success when the generator is rerun.
The gem owns parsing and Rails wiring behind the call, including `config.hosts`,
`Rails.application.default_url_options`, and Action Cable origins. It preserves
existing allowlists and unrelated URL options, and repeated calls do not add
duplicates. The public helpers read `TUNNEL_URL` on demand, but boot-time host
and Action Cable wiring requires a restart after environment changes.

In 1.x, the generator copied the parsing and wiring implementation into each
application. In 2.0, the application keeps the explicit call and the gem supplies
the implementation. After the one-time migration, wiring fixes arrive through
gem upgrades. The existing default/public helper names and their purposes remain
the same.

`AppUrl.base_url` delegates protocol and origin construction to Rails. An
omitted protocol follows Rails' effective default, including HTTPS when
`force_ssl` is enabled. Configured protocol spellings follow Rails, including
`http`, `https`, `http:`, and `https://`. Explicit empty protocols and malformed
values such as `http::` raise `ArgumentError` rather than being repaired.
`url_options` remains a passthrough to the application's defaults.
If you call URL helpers during configuration, set `protocol:` explicitly:
Rails applies the `force_ssl` protocol default later during initialization.

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
- Rails 7 support is retained and tested alongside Rails 8. Ruby 3.2 remains
  the minimum supported Ruby version.

The 2.0 installer does not rewrite copied application code. Upgrade an existing
app once:

1. Update the app's Gemfile to use the `v2.0.0` Git tag shown in
   [Installation](#installation), replacing any previous `ref:` pin, then run
   `bundle update app-url-rails`.
2. In `config/environments/development.rb`, remove only the complete old generated
   wiring for the `DEV_URL` and `TUNNEL_URL` branches. Remove `app_url_origin`
   only if no remaining custom configuration calls it. For example, an
   `OAUTH_BASE_URL` allowlist may still use that helper for Action Cable origins;
   preserve both the custom block and its helper. Keep application-specific
   webhook validation as well. If the app never installed the generated block,
   there is no copied wiring to remove.
3. Add the marker and setup call below inside the configure block. Put mailer
   assignments that consume `AppUrl.url_options` after this call.

```ruby
Rails.application.configure do
  # app-url-rails: configuration v1
  AppUrl.configure_development!(config)
end
```

4. Check the behavior changes above: environment URLs must be HTTP(S) origins,
   and set an explicit protocol if the app relied on the old HTTPS default.
5. Restart Rails and verify generated application/public URLs, host access, and
   Cable connections if used. Rerunning `bin/rails g app_url:install` after the
   replacement verifies the current installation and leaves it unchanged.

If the old block is partial, customized, ambiguous, or conflicts with the marker,
resolve it manually; the installer exits non-zero with an actionable diagnostic
and leaves the file unchanged. No migration script is needed: the migration is
replacing application configuration, and automatic rewriting could discard app
customizations. Once migrated, future gem upgrades use the existing call.

Apps using only URL helpers can continue without installing development setup;
the helper behavior changes above still apply.

## Known limitations

Route defaults such as `subdomain:` or `domain:` can cause Rails route helpers
to rewrite a supplied host. AppUrl handles host/protocol/port; applications using
those additional options must account for them when generating public URLs.

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

AppUrl 2.0 is a breaking release with these requirements:

- Ruby >= 3.2 (tested on Ruby 3.2 and 3.4)
- Rails >= 7.0 (tested on Rails 7.0, 7.1, 7.2, 8.0, and 8.1)

The gem declares Action Pack and Railties dependencies without a speculative
upper bound. Per-line Gemfiles in `gemfiles/` define the tested matrix; newer
Rails versions are allowed but need verification before being listed as tested.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/productmatter/app-url-rails). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventions.

## License

Released under the [Apache 2.0 License](LICENSE.txt).
