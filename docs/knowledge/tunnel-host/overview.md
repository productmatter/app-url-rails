# Tunnel domain allowance (`TUNNEL_HOST`)

`TUNNEL_URL` names one public origin; setup allows exactly that host.
`TUNNEL_HOST` covers the other shape tunnel tooling produces: per-session hosts
under one domain, such as git-treeline's `gtl share` links at
`https://s-<random>.<tunnel domain>`. It exists so applications never overload
`TUNNEL_URL` with a domain suffix, which would break every `AppUrl.public_*`
helper and fail validation at boot. The contract is archived at
[`archive/tunnel-host`](../../archive/tunnel-host/spec.md).

## How it works

`AppUrl.configure_development!` reads `TUNNEL_HOST` alongside `DEV_URL` and
`TUNNEL_URL`. Unset or empty means no change. A set value must be an ASCII
dotted hostname with no scheme, port, path, query, userinfo, or leading or
trailing dot. All three settings are validated before any configuration
changes, and errors name the setting and reason without echoing the value.

A valid domain adds `.<domain>` to `config.hosts` and one Action Cable origin
pattern accepting `https` on the domain or one subdomain label, on any port.
Repeated calls add nothing. `TUNNEL_HOST` never touches `default_url_options`
or any URL helper.

## Rules and rationale

- **One subdomain label, matching Rails.** A leading-dot `config.hosts` entry
  allows the apex and exactly one label on every supported Rails line (7.0
  through 8.1). The Cable pattern mirrors that rule so host authorization and
  Cable never disagree. Tunnel tooling issues single-label hosts.
- **Forwarded hosts count.** git-treeline's router and share proxy send
  `Host: 127.0.0.1:<port>` and the public host in `X-Forwarded-Host`; Rails
  checks both. The domain entry allows the forwarded host. The loopback `Host`
  passes only through Rails' default development IP allowance, so outside
  development those requests still answer 403.
- **`https` only for Cable.** Public tunnels terminate TLS at the provider.
- **Trusted domains only.** Sibling subdomains are same-site, so any page on
  the domain passes the Cable origin check with the developer's cookies. Use a
  domain where only you or trusted teammates create subdomains, and leave the
  variable unset in production.
- **No provider domains in the gem.** Quick-tunnel fallbacks such as
  `*.trycloudflare.com` belong in an application's local configuration.

With git-treeline, `.treeline.yml` maps `TUNNEL_HOST: "{tunnel_host}"`. The
token resolves per developer from their default named tunnel and is empty
without one.

## Corrections from the build

- `ENV` strings are binary under a C locale, so encoding validation checks the
  bytes as UTF-8 explicitly.
- The first Cable pattern accepted nested subdomains that Rails' host rule
  rejects; it was narrowed to one label.
- Case-insensitive matching folded non-ASCII lookalikes (the Kelvin sign) onto
  ASCII letters; the hostname check spells out `A-Z` instead.
