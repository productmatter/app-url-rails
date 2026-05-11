# git-treeline-rails

The conventional Rails integration for [git-treeline](https://github.com/git-treeline/git-treeline) worktrees. Adding the gem and running `gtl setup` is enough to get correct dev-environment routing — env vars loaded, `config.hosts` allowlisted, `default_url_options` set, cookies scoped per host. Development-only; no-ops in test/production.

## Prerequisites

The `gtl` CLI must be installed. The gem reads files written by it and shells out to `gtl routes --json` for tunnel discovery.

```bash
brew install git-treeline/tap/git-treeline
```

## Install

```ruby
# Gemfile
gem "git-treeline-rails", group: :development
```

Then per worktree:

```bash
gtl setup .
```

`gtl setup` allocates a port, database name, Redis namespace, and (if configured) a Cloudflare tunnel for the current worktree, writing the result to an env file (`.env.local` by default).

## What the gem does

At Rails boot, in development only:

1. **Loads the gtl-managed env file** into `ENV` using `||=` so explicit shell exports still win. Reads the target path from `env_file.target` in `.treeline.yml` (defaults to `.env.local`).
2. **Allowlists hosts**: appends the parsed `DEV_ACCESS_URL` host and a wildcard for the active tunnel parent domain (e.g. `.gtltunnel.dev`) to `config.hosts`.
3. **Sets `default_url_options`** on both `Rails.application` and `ActionMailer::Base` from `DEV_ACCESS_URL`.
4. **Defaults session cookie domain to `:all`** so cookies scope per request host (the spec-correct default per RFC 6265).

All four steps gracefully no-op when their inputs are absent.

## Conventional env vars

The gem reads four env vars. `gtl setup` writes them; non-gtl engineers set them by hand.

| Var | Purpose |
| --- | --- |
| `PORT` | What Puma binds to. |
| `DEV_ACCESS_URL` | Where the dev's browser hits the app — `http://localhost:PORT` for plain-localhost flows, or the gtl router URL (e.g. `http://salt-feature.prt.dev`). **Never the tunnel URL.** |
| `TUNNEL_PROVIDER` | `gtl`, `ngrok`, or `none`. Declares which inbound-access provider exposes the app to the outside world. |
| `NGROK_URL` | Full URL. Only consulted when `TUNNEL_PROVIDER=ngrok`. |

A typical gtl-managed `.treeline.yml` writes them like this:

```yaml
env:
  PORT: "{port}"
  DATABASE_NAME: "{database}"
  REDIS_URL: "{redis_url}"
  DEV_ACCESS_URL: "{router_url}"
  TUNNEL_PROVIDER: "gtl"
```

## Outsider-facing URLs (webhooks, callbacks, partner embeds)

`Rails.application.default_url_options` points at `DEV_ACCESS_URL` — correct for internal/admin UI. For URLs that need to be reachable from outside the dev's machine (webhook callbacks, consumer SMS links, Zapier responses, embed scripts hosted on partner sites), use the `TunnelUrl` helpers, which prefer the active tunnel URL and fall back to `DEV_ACCESS_URL`:

```ruby
TunnelUrl.url                   # full tunnel URL string, or nil when TUNNEL_PROVIDER=none
TunnelUrl.host                  # tunnel host, or nil
TunnelUrl.public_url_options    # { host:, protocol:, port: } for use with *_url helpers
TunnelUrl.public_base_url       # full URL string (tunnel preferred, falls back to DEV_ACCESS_URL)
```

Example — generating a webhook callback URL:

```ruby
callback_url = my_webhook_url(**TunnelUrl.public_url_options)
```

Choosing which call sites use `public_url_options` vs. `default_url_options` is the app's call. The gem provides the helpers; you decide where outsider-reachability matters.

## Custom tunnel providers

Built-in providers are `gtl`, `ngrok`, and `none`. Register your own in `config/application.rb` so it's available before the host-allowlist initializer runs:

```ruby
# config/application.rb
Bundler.require(*Rails.groups)

TunnelUrl.register(:my_provider) do
  MyProviderClient.current_public_url
end

module MyApp
  class Application < Rails::Application
    # ...
  end
end
```

The registered block is invoked once per process when `TunnelUrl.url` is first called. Set `TUNNEL_PROVIDER=my_provider` in `.env.local` to activate it. Blocks should return a URL string or raise on failure.

## Configuration options

Configure under `config.git_treeline_rails` — typically in `config/application.rb` or `config/environments/development.rb`:

```ruby
# Opt out of the cookie-domain default. By default the gem sets
# config.session_options[:domain] = :all in development. Set to nil
# to leave the app's session_store config untouched.
config.git_treeline_rails.cookie_domain = nil
```

## Known limitations

- **Wildcard host requires the tunnel to be up at boot.** The Railtie discovers the tunnel parent domain from the active tunnel URL. If you boot Rails without a tunnel running, the wildcard is not added — starting the tunnel afterward will work for that specific URL only if Rails is restarted. Workaround: start the tunnel before booting Rails.
- **`localhost` and tunnel cookies are separate jars.** RFC 6265 scopes cookies per request host; there is no parent domain shared between `localhost` and `<branch>.prt.dev`. If you switch between the two mid-session you will sign in twice. This is intentional — bridging the two would require an SSO-style redirect dance with real attack surface.
- **ngrok URLs are hand-set, not auto-discovered.** ngrok's local API (`:4040/api/tunnels`) is ambiguous when multiple agents run on one machine, and there's no per-worktree registry. Set `NGROK_URL` and restart Rails when the URL changes.

## Development-only

The Railtie returns early outside of `Rails.env.development?`. Production URL configuration, host allowlists, and cookie behavior remain entirely the app's responsibility.

## License

Apache-2.0. See `LICENSE.txt`.
