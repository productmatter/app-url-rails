# tunnel-url-rails

Tiny, provider-agnostic helper for generating outsider-reachable URLs in Rails
apps that have a tunnel set up for development.

## What it does

You set `TUNNEL_URL` to whatever your tunnel agent gave you (ngrok, Cloudflare
Tunnel, anything else). At request time, your app's webhook callbacks,
consumer-facing SMS links, partner-facing API responses, etc., can use
`TunnelUrl.public_url_options` to get a hash suitable for Rails' `*_url`
helpers — tunnel URL preferred, falls back to your app's
`default_url_options`.

That's all.

## What it doesn't do

- Tell Rails about `config.hosts` — you do this in `development.rb` (see
  [Setup](#setup-developmentrb)).
- Set `default_url_options` — you do this in `development.rb` (see
  [Setup](#setup-developmentrb)).
- Auto-discover your tunnel URL — you set `TUNNEL_URL` however you want (env
  file, tunnel-agent script, shell export).
- Manage cookies, OAuth, or anything else.

## Install

```ruby
# Gemfile
group :development, :test do
  gem "tunnel-url-rails"
end
```

```sh
bundle install
```

(Production doesn't need the gem — call sites that reference `TunnelUrl` only
fire when `TUNNEL_URL` is set, which is a development-environment concern. If
you prefer to require it in all groups for simplicity, that's fine too.)

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

## Setup (`development.rb`)

The gem deliberately does **not** wire `config.hosts` or `default_url_options`
for you. Add these lines to `config/environments/development.rb`:

```ruby
Rails.application.configure do
  # ... existing config ...

  if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
    uri = URI(tunnel)
    config.hosts << uri.host
    routes.default_url_options = { host: uri.host, protocol: uri.scheme }
  end
end
```

This must run during config-time (inside the `configure` block), **not** in an
initializer or `config.after_initialize`. `ActionDispatch::HostAuthorization`
snapshots `config.hosts` during `Rails.application.initialize!`, so any host
added after that point is silently ignored.

## Why this isn't a Railtie

The wiring above is a handful of inline lines with one non-obvious constraint
(the phase-ordering rule about `HostAuthorization`). That constraint is more
honestly captured by a comment in your app's `development.rb` than by a
Railtie that hides the timing. The class is what's worth sharing across
apps; the wiring isn't.

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
