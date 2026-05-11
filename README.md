# git-treeline-rails

Add this gem to your Gemfile and run `gtl setup`. Your Rails development environment now accepts requests via both your gtl-allocated dev access URL (`http://localhost:PORT` or `https://<branch>.prt.dev`) **and** any public Cloudflare tunnel URL gtl has allocated for the worktree — including across tunnel-agent restarts, with no Rails restart needed.

Development-only. The gem returns early outside `Rails.env.development?`; production URL config, host allowlisting, and cookie behavior remain entirely your app's responsibility.

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

## What the gem auto-wires

At Rails boot, in development only:

1. **Loads the gtl env file** into `ENV` using `||=` so explicit shell exports still win. Reads the target path from `env_file.target` in `.treeline.yml` (defaults to `.env.local`).
2. **Allowlists hosts**: appends `URI(DEV_ACCESS_URL).host` and a wildcard for the configured tunnel parent domain (e.g. `.gtltunnel.dev`) to `config.hosts`.
3. **Sets `default_url_options`** on both `Rails.application` and `ActionMailer::Base` from `DEV_ACCESS_URL`.

All three steps gracefully no-op when their inputs are absent. None of them run outside development.

## Conventional env vars

| Var | Purpose |
| --- | --- |
| `PORT` | What Puma binds to. |
| `DEV_ACCESS_URL` | Full URL where the dev's browser hits the app — `http://localhost:PORT` for localhost flows, or the gtl router URL (e.g. `https://salt-feature.prt.dev`). **Never the tunnel URL.** |
| `TUNNEL_PROVIDER` | `gtl`, `ngrok`, or `none`. Declares which inbound-public-access provider exposes the app. |
| `NGROK_URL` | Full URL. Read only when `TUNNEL_PROVIDER=ngrok`. Hand-set. |

A typical gtl-managed `.treeline.yml` writes them like this:

```yaml
env:
  PORT: "{port}"
  DATABASE_NAME: "{database}"
  REDIS_URL: "{redis_url}"
  DEV_ACCESS_URL: "{router_url}"
  TUNNEL_PROVIDER: "gtl"
```

A committed `.env` should provide defaults for non-gtl engineers:

```
DEV_ACCESS_URL=http://localhost:3000
TUNNEL_PROVIDER=none
```

### Why `DEV_ACCESS_URL` (not `DEV_APPLICATION_URL`)

`DEV_ACCESS_URL` is intentionally not named to parallel `APPLICATION_HOST`. It's a different concept, not a dev override of the same one:

- `APPLICATION_HOST` (production) = "where this app lives on the public internet."
- `DEV_ACCESS_URL` (development) = "where the engineer's browser accesses the dev app."

The distinct name signals the distinct meaning. Keep `APPLICATION_HOST` as-is in your production config; this gem doesn't touch it.

## Outsider-facing URLs

`Rails.application.default_url_options` points at `DEV_ACCESS_URL` — correct for internal/admin UI that the developer browses to directly.

**Rule:** default to `default_url_options`. Reach for `TunnelUrl.public_url_options` *only* when the generated URL is being handed to something external to the developer's machine — webhook callbacks, consumer SMS links, Zapier responses, partner-embedded iframes hosted at external sites.

```ruby
TunnelUrl.url                   # full tunnel URL string, or nil when TUNNEL_PROVIDER=none
TunnelUrl.host                  # tunnel host, or nil
TunnelUrl.public_url_options    # { host:, protocol:, port: } for *_url helpers (tunnel preferred, falls back to DEV_ACCESS_URL)
TunnelUrl.public_base_url       # full URL string (tunnel preferred, falls back to DEV_ACCESS_URL)
```

Example — webhook callback:

```ruby
callback_url = stripe_webhook_url(**TunnelUrl.public_url_options)
```

In production, `TUNNEL_PROVIDER=none`, the helpers fall back to `default_url_options` (= the production URL), so the same call site works in both environments.

## Custom tunnel providers

Built-in providers are `:gtl`, `:ngrok`, and `:none`. Register your own in `config/application.rb` so it's available before the host-allowlist initializer runs:

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

The registered block runs once per process when `TunnelUrl.url` is first called. Activate with `TUNNEL_PROVIDER=my_provider`. Blocks should return a URL string or raise on failure.

## Testing it works

This walkthrough proves the gem is doing what it claims — that Rails accepts tunnel URLs across tunnel-agent restarts without a Rails reboot.

1. **Tunnel agent down, Rails down.** Starting state.
2. **`gtl start`** — Rails boots. At boot, the gem reads `gtl routes --json` and appends the configured tunnel parent domain (e.g. `.gtltunnel.dev`) as a wildcard to `config.hosts`. The cloudflared agent does not need to be running for this lookup — `gtl routes --json` returns the deterministic tunnel URL whether the agent is up or down.
3. **Hit the tunnel URL in a browser.** Expect a Cloudflare error page (no agent forwarding requests). This is *not* a Rails problem — Rails never sees the request.
4. **`gtl tunnel`** in another terminal. Cloudflared starts forwarding.
5. **Refresh the tunnel URL.** Expect Rails' usual sign-in redirect (or whatever your app does on `/`). **No Rails restart between steps 4 and 5.**
6. **Stop the tunnel agent.** The URL fails again. Rails is still running.
7. **Restart the tunnel agent.** The URL works again. **Still no Rails restart.**

If step 5 fails with `Blocked host: ...`, the wildcard wasn't added at boot — confirm `gtl routes --json` returns a `tunnel` field in this worktree (`gtl tunnel setup` must have been run for the worktree).

## Still your responsibility

The gem deliberately leaves these to your app:

- **Production URL/host configuration** (`APPLICATION_HOST` or equivalent). The gem only operates in development.
- **`config.force_ssl` / forwarded-proto handling.** Apps behind the gtl router or any HTTPS proxy need their own middleware/config so Rails generates `https://` URLs and trusts `X-Forwarded-Proto`.
- **OAuth callback host configuration.** Fixed contract with the OAuth provider; usually a dedicated env var like `OAUTH_BASE_URL`.
- **Session cookie domain in development.** See the recipe below.
- **Webhook signature/host validation.** Stripe subdomain checks, etc.
- **Asset host configuration.**
- **Per-call-site decisions** about which URL flavor to use (`default_url_options` vs `TunnelUrl.public_url_options`). See the rule above.
- **Test environment URL config.** See the migration guide below.

## Cookie domain recipe

If your app reads a session cookie domain from ENV (or hard-codes one that doesn't match the request host), the browser rejects every Set-Cookie and you get a Devise/Warden redirect storm. The spec-correct fix for development is one line:

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: "_yourapp_session",
  domain: ::Rails.env.development? ? :all : nil
```

`:all` tells Rails to scope the cookie per request host (per RFC 6265). Production keeps the default cookie behavior. Note: this means `localhost` and `<branch>.prt.dev` have *separate* cookie jars — there is no common parent domain, so switching between them mid-session signs you in twice. That's intentional; bridging the two requires an SSO-style redirect with real attack surface.

## Migration from `APPLICATION_HOST` + `PROTOCOL`

Apps currently using the conventional `APPLICATION_HOST` + `PROTOCOL` split:

1. **Keep `APPLICATION_HOST` as-is for production.** Don't rename it globally.
2. **Add `DEV_ACCESS_URL` to `.env`** with the localhost default:
   ```
   DEV_ACCESS_URL=http://localhost:3000
   TUNNEL_PROVIDER=none
   ```
3. **Wire test env** — without `DEV_ACCESS_URL` set (and this gem inert outside dev), `Rails.application.default_url_options` is empty in tests. Route helpers without explicit `host:` will raise `Missing host to link to!`. Add to `config/environments/test.rb`:
   ```ruby
   Rails.application.default_url_options = { host: "localhost", port: 3000 }
   ```
4. **Update app code** that reads `ENV["APPLICATION_HOST"]` + `ENV["PROTOCOL"]` directly to instead use `Rails.application.default_url_options`. The gem populates it in dev from `DEV_ACCESS_URL`; your `production.rb` populates it from your prod env vars.
5. **Audit outsider-facing URL generation** sites (webhook callbacks, consumer SMS, Zapier responses, partner embeds) and migrate them to `TunnelUrl.public_url_options`.
6. **Drop dead env vars** previously used for one-off URL piecing: `TUNNEL_HOST`, `OAUTH_CALLBACK_HOST` (if it was synthesized from other vars), `SESSION_COOKIE_DOMAIN` (replaced by the cookie recipe above).

## Known limitations

- **Wildcard host requires the worktree to have a tunnel configured.** `gtl tunnel setup` must have been run for this worktree so that `gtl routes --json` returns a tunnel URL — the wildcard parent domain is derived from it. The cloudflared agent itself does *not* need to be running at Rails boot; the URL is deterministic regardless of agent state.
- **`localhost` and `*.prt.dev` cookies are separate jars.** RFC 6265 scopes cookies per request host; no parent domain is shared. Switching between the two mid-session signs you in twice. Bridging requires an SSO-style redirect with real attack surface — out of scope.
- **ngrok URLs are hand-set, not auto-discovered.** ngrok's local API (`:4040/api/tunnels`) is ambiguous when multiple agents run on one machine, and there's no per-worktree registry. Set `NGROK_URL` and restart Rails when the URL changes.

## License

Apache-2.0. See `LICENSE.txt`.
