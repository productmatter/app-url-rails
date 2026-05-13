# app-url-rails

One place to get your Rails app's URL — replacing the host/port string-building
scattered across controllers, mailers, and service objects. Adds an optional
tunnel override for outsider-reachable URLs in development (webhook callbacks,
SMS links, OAuth redirects, partner API responses).

## Why this exists

Most Rails apps end up hand-building URLs in lots of places: `request.host`,
`Rails.application.routes.default_url_options`, hard-coded `ENV` reads, the
occasional `URI.join`, format strings like `"#{scheme}://#{host}:#{port}"`. It
works until you need to change how the URL is computed, and then every callsite
needs to be updated.

`AppUrl` is one place to ask: "what's this app's URL right now?" Production,
development, with a tunnel, without one — same call, correct answer.

## What it gives your app

- **`AppUrl.base_url`, `AppUrl.host`, `AppUrl.url_options`** — the app's URL
  as currently configured. Use these anywhere you'd otherwise hand-build a URL
  from `default_url_options` or `request.host`.
- **`AppUrl.public_base_url`, `AppUrl.public_host`, `AppUrl.public_url_options`** —
  the outsider-reachable URL. Returns `TUNNEL_URL` when set; falls back to the
  app's configured URL otherwise. Use these for webhook callbacks, SMS links,
  OAuth redirects, and anything else an outside system needs to reach.
- **An install generator** that wires `DEV_URL` and `TUNNEL_URL` into
  `config/environments/development.rb` at the right phase. No Railtie, no
  autoloaded initializer — visible code in your repo.

## Production behavior

The gem reads `DEV_URL` and `TUNNEL_URL` only. In production both are typically
unset, so:

- `AppUrl.base_url` / `AppUrl.host` / `AppUrl.url_options` return values
  derived from `Rails.application.default_url_options`, which your app sets
  from its production config (`APPLICATION_HOST` or your equivalent).
- `AppUrl.public_*` methods fall back to the same defaults — no divergence
  from the app's canonical URL in prod.
- Nothing else runs. No Railtie, no initializer, no request-cycle hooks.

The install generator modifies `config/environments/development.rb` only.
Production paths are untouched.

## Install

```sh
bundle add app-url-rails
bin/rails g app_url:install
```

The generator injects a wiring block into `config/environments/development.rb`.
It's idempotent — safe to re-run, skips if `DEV_URL` or `TUNNEL_URL` are
already referenced.

With neither env var set, your dev environment behaves exactly as it did
before. Set `DEV_URL` when your browser accesses the app at something other
than `localhost` (e.g. git-treeline, Tailscale, custom DNS). Set `TUNNEL_URL`
when you need a publicly-reachable URL (Cloudflare tunnel, ngrok).

## Env vars

| Var | Role | Required? |
| --- | --- | --- |
| `DEV_URL` | Where the engineer's browser hits the app in development. Wires `Rails.application.default_url_options` and adds the host to `config.hosts`. | Optional |
| `TUNNEL_URL` | Where outsiders reach the app in development. Surfaces via `AppUrl.public_*`; also added to `config.hosts`. | Optional |

Both optional. Both development-only by convention; the gem itself reads them
in any environment, but production typically sets neither.

## Usage

```ruby
# The app's URL (production, development, anywhere)
AppUrl.host
# => "yourapp.com" (or "localhost", or whatever default_url_options[:host] is)

AppUrl.url_options
# => { host: "yourapp.com", protocol: "https" }

AppUrl.base_url
# => "https://yourapp.com"

# The outsider-reachable URL (webhook callbacks, SMS links, OAuth, etc.)
AppUrl.public_host
# => "abc.ngrok-free.app" (TUNNEL_URL host), else the app's host

AppUrl.public_url_options
# => { host: "abc.ngrok-free.app", protocol: "https" }
# Falls back to AppUrl.url_options when TUNNEL_URL is unset.

AppUrl.public_base_url
# => "https://abc.ngrok-free.app" (or AppUrl.base_url when TUNNEL_URL is unset)

AppUrl.public_url
# => "https://abc.ngrok-free.app" (raw TUNNEL_URL value, or nil if unset)
```

Typical use in a controller, mailer, or service:

```ruby
# Internal-facing — admin link, in-app redirect
redirect_to dashboard_url(**AppUrl.url_options)

# Outsider-facing — webhook callback, SMS link, OAuth redirect
callback = some_callback_url(**AppUrl.public_url_options, token: t)
```

## What the generator does

The generator injects this block inside `Rails.application.configure do` in
`config/environments/development.rb`:

```ruby
# app-url-rails: dev URL + tunnel URL wiring.
# Must run at config-time — Rails snapshots config.hosts during initialize!,
# so adding hosts later (initializer, after_initialize) is silently ignored.
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

This must run at **config-time** (inside the `configure` block), not in an
initializer or `config.after_initialize`. `ActionDispatch::HostAuthorization`
snapshots `config.hosts` during `Rails.application.initialize!`, so any host
added after that point is silently ignored. The generator puts the block in
the right place so you don't have to think about it.

Prefer to paste this manually? That's fine — the gem doesn't care how the
env vars or host config get set up. The class just reads
`Rails.application.default_url_options` and `ENV["TUNNEL_URL"]`.

## Using with git-treeline

If you use [git-treeline](https://github.com/git-treeline/git-treeline) (or
any tool that runs multiple worktrees in parallel), each workspace can carry
its own `DEV_URL` and `TUNNEL_URL`. Treeline sets them dynamically when a
workspace starts, so parallel branches each get distinct internal and public
URLs without you editing `.env` by hand or juggling tunnel agents.

`AppUrl` reads whatever's in the environment at request time, so there's
nothing extra to wire up beyond the generator — the gem is deliberately
agnostic about how the env vars got there.

## Why this isn't a Railtie

The wiring is a handful of inline lines with one non-obvious constraint (the
phase-ordering rule about `HostAuthorization`). That constraint is more
honestly captured by visible code in your app's `development.rb` than by a
Railtie that hides the timing. The class is what's worth sharing across apps;
the wiring isn't.

The install generator is a one-shot that writes the wiring into your repo —
visible, editable, version-controlled. Nothing runs at boot from the gem
itself.

## Caveat: session cookies on Public Suffix List hosts

This gem doesn't touch cookies, but if you're using a tunnel provider whose
domain is on the [Public Suffix List](https://publicsuffix.org/) — `ngrok.io`,
`ngrok-free.app`, `vercel.app`, `herokuapp.com`, etc. — be aware:

- Rails' `session_store :cookie_store, domain: :all` will compute a `Domain=`
  attribute pointing at the public suffix (e.g. `.ngrok-free.app`).
- Browsers reject `Set-Cookie` whose `Domain=` is a public suffix.
- Result: session cookie silently dropped, redirect loop on sign-in.

Fix in your app's `config/initializers/session_store.rb`: use host-only
cookies in development (omit `domain:` or set `domain: nil`). Production
keeps whatever cookie domain you actually need.

```ruby
Rails.application.config.session_store :cookie_store,
  key: "_yourapp_session",
  domain: (Rails.env.production? ? ENV["SESSION_COOKIE_DOMAIN"].presence : nil)
```

## License

Apache-2.0. See [LICENSE.txt](LICENSE.txt).
