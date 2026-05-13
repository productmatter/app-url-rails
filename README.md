# tunnel-url-rails

Tiny, provider-agnostic helper for Rails apps that need outsider-reachable
URLs during local development — webhook callbacks, OAuth redirects, SMS links,
partner API responses. Reads `TUNNEL_URL` from the environment. **Touches
nothing in production.**

## Why this exists

Most Rails apps end up with host-building logic scattered across controllers,
mailers, and service objects — `request.host`, `Rails.application.routes.default_url_options`,
hard-coded `ENV` reads, the occasional `URI.join`. It works until something
outside your laptop needs the URL: a webhook callback, an SMS link, a partner
API response, an OAuth redirect. Then you add a tunnel, and every one of those
call sites needs to know about it.

`TunnelUrl` is one place to ask "what host should outsiders use right now?" —
tunnel if set, otherwise your app's configured host. Call sites stop caring
whether they're in development or production.

## What it gives your app

- A single API for outsider-reachable URLs — `TunnelUrl.public_url_options` —
  that you can pass to any Rails `*_url` helper.
- Automatic fallback to `Rails.application.default_url_options` when
  `TUNNEL_URL` is unset. Call sites don't branch on environment.
- Provider-agnostic. ngrok, Cloudflare Tunnel, anything that hands you a URL.
- No Railtie, no autoloaded initializer, no monkey patches. Just a class plus
  a one-shot install generator that writes visible code into your repo.

## Production behavior

This gem only matters when `TUNNEL_URL` is set, which is a local-development
concern. In production, `TUNNEL_URL` is unset, so:

- `TunnelUrl.public_url_options` returns exactly
  `Rails.application.default_url_options`.
- `TunnelUrl.public_base_url` returns the URL assembled from those same
  options.
- Nothing else runs. There's no Railtie, no initializer, no hook into the
  request cycle.

Your production URL generation is unchanged. Put the gem in `:development,
:test` only or in all groups — either is fine.

## Install

```sh
bundle add tunnel-url-rails --group "development test"
bin/rails g tunnel_url:install
```

The generator injects a `TUNNEL_URL` block into
`config/environments/development.rb`. It's idempotent — safe to re-run, skips
if the block is already present.

That's the entire setup. With no `TUNNEL_URL` in the environment, your app
boots and behaves exactly as it did before.

## Usage

```ruby
TunnelUrl.url
# => "https://abc.ngrok-free.app"  (or nil if TUNNEL_URL is unset/empty)

TunnelUrl.host
# => "abc.ngrok-free.app"          (or nil)

TunnelUrl.base_url
# => "https://yourapp.com"         (assembled from Rails.application.default_url_options)

TunnelUrl.public_url_options
# => { host: "abc.ngrok-free.app", protocol: "https" }
# Falls back to Rails.application.default_url_options when TUNNEL_URL is unset.

TunnelUrl.public_base_url
# => "https://abc.ngrok-free.app"  (or base_url when TUNNEL_URL is unset)
```

Typical use in a controller, mailer, or service:

```ruby
redirect_to some_callback_url(**TunnelUrl.public_url_options, token: t)
```

## What the generator does

The generator injects this block inside `Rails.application.configure do` in
`config/environments/development.rb`:

```ruby
if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
  require "uri"
  uri = URI(tunnel)
  config.hosts << uri.host
  routes.default_url_options = { host: uri.host, protocol: uri.scheme }
end
```

This must run at **config-time** (inside the `configure` block), not in an
initializer or `config.after_initialize`. `ActionDispatch::HostAuthorization`
snapshots `config.hosts` during `Rails.application.initialize!`, so any host
added after that point is silently ignored. The generator puts the block in
the right place so you don't have to think about it.

Prefer to paste this manually? That's fine — the gem doesn't care how the env
var or host config gets set up.

## Using with git-treeline

If you use [git-treeline](https://github.com/git-treeline/git-treeline) (or
any tool that runs multiple worktrees in parallel), each workspace can carry
its own `TUNNEL_URL`. Treeline sets it dynamically when a workspace starts,
so parallel branches each get an outsider-reachable URL without you editing
`.env` by hand or juggling tunnel agents.

`TunnelUrl` reads whatever's in the environment at request time, so there's
nothing extra to wire up beyond the generator — the gem is deliberately
agnostic about how `TUNNEL_URL` got there.

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
