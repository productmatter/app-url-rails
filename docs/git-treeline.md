# git-treeline and AppUrl Adoption

This guide is for Rails apps that install `app-url-rails` and need to connect
git-treeline-managed URLs to the rest of the Rails stack. It is written so
humans and coding agents can detect a git-treeline app, understand how
git-treeline should feed `AppUrl`, and know which app-level call sites still
need deliberate wiring.

## The Contract

`app-url-rails` only requires environment variables. It does not require
git-treeline.

| Variable | Meaning | Typical source |
| --- | --- | --- |
| `PORT` | Port your Rails server binds to. | `bin/dev`, Procfile, git-treeline |
| `DEV_URL` | Browser-facing app URL used for Rails URL helpers and `AppUrl.base_url`. | Manual env or git-treeline router URL |
| `TUNNEL_URL` | Optional public URL for webhooks, SMS links, email links, Slack links, partner embeds, and other outside callers. | ngrok, Cloudflare Tunnel, git-treeline tunnel |

`DEV_URL` drives internal app URLs. `TUNNEL_URL` drives outsider-facing URLs
through `AppUrl.public_*`. Keep them separate unless your development URL is
also publicly reachable.

## Detecting a git-treeline App

A Rails app is git-treeline-aware if the repo has a `.treeline.yml` file.
Read that file before changing URL configuration.

Look for:

```yaml
env_file: .env.local

env:
  PORT: "{port}"
  DEV_URL: "{router_url}"
  TUNNEL_URL: "{tunnel_url}"
```

The important parts are:

- `env_file` tells you which env file git-treeline writes. Common values are
  `.env.local` and `.env.development`.
- `PORT: "{port}"` tells Rails where to bind.
- `DEV_URL: "{router_url}"` gives Rails a per-worktree browser URL.
- `TUNNEL_URL: "{tunnel_url}"` gives outsider-facing links a per-worktree
  public URL when tunnel support is configured.

If `.treeline.yml` exists but does not set `DEV_URL`, add it. If the app uses
outside callbacks, email links, SMS links, Slack links, or webhook URLs in
development, add `TUNNEL_URL` too.

Use git-treeline commands to inspect the live values:

```sh
gtl env
gtl status --json
gtl routes --json
```

`app-url-rails` does not call `gtl` at runtime. git-treeline feeds env vars;
Rails boots with those env vars; `AppUrl` reads Rails defaults and
`TUNNEL_URL`.

## How Values Flow Through Rails

The intended flow is:

```text
.treeline.yml or manual env
  -> PORT / DEV_URL / TUNNEL_URL
  -> config/environments/development.rb
  -> Rails.application.default_url_options
  -> AppUrl.url_options / AppUrl.base_url
  -> AppUrl.public_url_options / AppUrl.public_base_url
  -> app call sites
```

The install generator wires the config-time layer:

- `config.hosts` gets the `DEV_URL` host and, when set, the `TUNNEL_URL` host.
- `Rails.application.default_url_options` is derived from `DEV_URL`.
- `config.action_cable.allowed_request_origins` accepts the `DEV_URL` and
  `TUNNEL_URL` scheme/host on any port in development.

The generator does not know which URLs in your app are internal versus
outsider-facing. Engineers still need to map app call sites to the correct
`AppUrl` helper.

## App-Level Wiring Checklist

After running `bin/rails g app_url:install`, search the app for URL generation
and host configuration:

```sh
rg "_url\\b|default_url_options|asset_host|host:|protocol:|ENV\\[.*URL|request\\.host|request\\.base_url"
```

Review these areas:

| Area | Usually use | Why |
| --- | --- | --- |
| In-app redirects and admin links | `AppUrl.url_options` | The browser should stay on `DEV_URL`. |
| Rails routes defaults | `AppUrl.url_options` | App-generated URLs need one canonical browser-facing host. |
| Action Mailer `default_url_options` | Usually `AppUrl.url_options` | Mailer route helpers need a host. |
| Action Mailer `asset_host` | Often `AppUrl.public_base_url` | Email images/assets may be opened outside the dev machine. |
| Webhook callback URLs | `AppUrl.public_url_options` | External services must call the tunnel/public URL. |
| SMS, Slack, and notification links for real recipients | `AppUrl.public_url_options` | Recipients are outside the local browser session. |
| OAuth metadata for local desktop clients | Usually `AppUrl.base_url` | The client opens the local/router URL in the developer's browser. |
| OAuth callbacks for cloud providers | App-specific | Often requires a stable public URL registered with the provider. |
| Partner embeds or externally loaded frames | `AppUrl.public_url_options` | The partner system must reach the app from outside. |
| API serializers that expose links | Depends on audience | Internal clients use `DEV_URL`; external clients use `TUNNEL_URL`. |
| Seeds or demo data that include links | Depends on audience | Avoid baking localhost into data shown to external testers. |

Examples:

```ruby
# Internal/browser-facing URL
redirect_to dashboard_url(**AppUrl.url_options)

# External callback
WebhookClient.register(callback_url: webhook_url(**AppUrl.public_url_options))

# Mailer defaults
config.action_mailer.default_url_options = AppUrl.url_options
config.action_mailer.asset_host = AppUrl.public_base_url
```

When in doubt, ask who clicks or calls the URL:

- Developer's browser in this Rails session: use `AppUrl.url_options` or
  `AppUrl.base_url`.
- External service, phone, email client, Slack client, partner app, or webhook
  provider: use `AppUrl.public_url_options` or `AppUrl.public_base_url`.

## Without git-treeline

For a normal single checkout, configure `PORT` and `DEV_URL` in the same place
your app already loads development env vars, such as `.env`, `.env.local`, or
`.env.development`.

```sh
PORT=3000
DEV_URL=http://localhost:3000
```

If you run Rails on a different port, update both values together:

```sh
PORT=4321
DEV_URL=http://localhost:4321
```

Set `TUNNEL_URL` only when an outside service needs to reach your local app.

```sh
TUNNEL_URL=https://your-subdomain.ngrok-free.app
```

Restart Rails after changing `DEV_URL` or `TUNNEL_URL`. The install generator
adds hosts and Action Cable origins during Rails configuration, so boot-time
values matter.

## With git-treeline

git-treeline can allocate per-worktree ports, databases, Redis namespaces, and
development URLs. In that setup, let `.treeline.yml` write `DEV_URL` and
`TUNNEL_URL` into the env file your app loads.

Example:

```yaml
env_file: .env.local

env:
  PORT: "{port}"
  DEV_URL: "{router_url}"
  TUNNEL_URL: "{tunnel_url}"
```

Some apps use `.env.development` instead of `.env.local`; either is fine as
long as Rails loads it before `config/environments/development.rb` evaluates.

Typical setup:

```sh
gtl setup .
gtl start --await
```

If a Rails app already has `.treeline.yml`, prefer updating that file over
hand-editing generated env values. Regenerate/sync the env file afterward with
the workflow that app uses, such as `gtl setup .` or `gtl env sync`.

## Why DEV_URL May Be Portless

git-treeline router URLs can intentionally present a clean URL to the app, such
as:

```sh
DEV_URL=https://my-branch.prt.dev
```

The browser's actual origin may still include a router port, such as:

```text
https://my-branch.prt.dev:3001
```

Do not "fix" that by forcing the route port into `DEV_URL` if your app expects
clean generated links. `DEV_URL` is the canonical URL Rails helpers should
render. Action Cable origin checks are the special case: they must accept the
browser origin that actually opens `/cable`.

The install generator handles this by allowing Action Cable origins on the same
scheme and host with any port in development:

```ruby
%r{\A#{Regexp.escape(uri.scheme)}://#{Regexp.escape(uri.host)}(?::\d+)?\z}i
```

This keeps the host boundary intact while tolerating router/proxy port
differences.

## Security Scope

The port-tolerant Action Cable origin is development wiring. It is appropriate
for git-treeline, local tunnels, and reverse proxies where the same dev host may
appear on different ports.

It is not a production allowlist pattern. Production apps should use exact,
known origins unless they deliberately want same-host-any-port behavior.

## App Install Checklist

When installing `app-url-rails` in another Rails app:

1. Add the gem and run `bin/rails g app_url:install`.
2. Confirm the app loads its dev env file before Rails environment config runs.
3. If `.treeline.yml` exists, ensure it writes `DEV_URL: "{router_url}"` and,
   when useful, `TUNNEL_URL: "{tunnel_url}"`.
4. Without git-treeline, set `PORT` and `DEV_URL` manually in the app's dev env
   file.
5. Search app call sites with the command in "App-Level Wiring Checklist".
6. Use `AppUrl.url_options` or `AppUrl.base_url` for internal/browser-facing links.
7. Use `AppUrl.public_url_options` or `AppUrl.public_base_url` only for outsider-facing links.
8. Restart Rails after changing `DEV_URL` or `TUNNEL_URL`.

## Generator Scope

The install generator intentionally limits itself to
`config/environments/development.rb`. That file is safe to update because every
app needs the same config-time host, default URL, and Action Cable wiring.

The generator should not automatically rewrite mailers, jobs, serializers,
OAuth metadata, webhook clients, or notification services. Those call sites are
semantic: the correct helper depends on whether the URL is for the developer's
browser or for an outside system.

A useful future generator would be non-mutating:

```sh
bin/rails g app_url:audit
```

That audit could report likely URL call sites, env files, `.treeline.yml`
settings, and current Rails defaults without editing app code. Until such a
tool exists, this guide is the adoption map.

## Troubleshooting

If Rails raises `Blocked hosts`, inspect:

```sh
bin/rails runner 'puts Rails.application.config.hosts.inspect'
```

If URL helpers raise `Missing host to link to`, `DEV_URL` is missing or was not
loaded before development config ran.

If Turbo Stream broadcasts publish but never update the browser, check Action
Cable first. A common cause is a WebSocket rejected because the browser origin
has a router port while old development wiring only allowed the portless
`DEV_URL`.

If a public webhook, SMS, email, or partner link points at localhost, set
`TUNNEL_URL` and make that call site use `AppUrl.public_*`.
