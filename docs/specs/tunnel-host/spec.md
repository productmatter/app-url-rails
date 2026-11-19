---
slug: tunnel-host
type: feature
status: building
decider: jonathan
created: 2026-11-18
build: attended
blast_radius: low
size: small
---

# Allow a tunnel domain, not only the tunnel host

## Goal

With `TUNNEL_HOST=tunnels.example`, a real Rails boot answers 200 to the domain
and its immediate subdomains (direct or forwarded) and accepts their `https`
Cable origins. `TUNNEL_URL` continues to drive the public URL helpers.

## Intent

`TUNNEL_URL` names one public origin, and setup allows exactly that host. Tunnel
tooling also hands out per-session hosts under the same domain: git-treeline's
`gtl share` serves `s-<random>.<tunnel domain>`, and its own Rails hint is a
domain wildcard (`config.hosts << ".<domain>"`). With no gem affordance for the
domain, an application developer edited the copied wiring block and overloaded
`TUNNEL_URL` with a bare suffix (truherd/wildlife_platform#706), which breaks
every `AppUrl.public_*` helper and fails validation in 2.0. Jonathan authorized
this change on 2026-11-18. Appetite: one optional environment variable, its
validation, host and Cable wiring, tests, and documentation.

## Non-goals

- Changing what `TUNNEL_URL` means or how the public helpers resolve it.
- Hard-coding any provider domain such as `trycloudflare.com` in the gem.
- Changing the install generator, the configuration marker, or the 1.x migration.
- Releasing or publishing the gem.

## Behavior

1. `AppUrl.configure_development!(config)` reads an optional `TUNNEL_HOST`.
   Unset or empty means no change, matching `DEV_URL` and `TUNNEL_URL`.
2. A set `TUNNEL_HOST` must be a bare dotted hostname such as `tunnels.example`:
   no scheme, port, path, query, fragment, userinfo, or leading/trailing dot.
   Invalid values raise `AppUrl::ConfigurationError` before any Rails
   configuration changes, naming the setting and reason without echoing the
   raw value. All three environment settings are validated before mutation.
3. Setup appends `.<TUNNEL_HOST>` to `config.hosts`, so Rails host authorization
   accepts the domain and its immediate subdomains, including hosts forwarded
   by a local proxy.
4. When Action Cable is configured, setup appends one origin pattern accepting
   `https://` on the domain or an immediate subdomain, on any port. Setup preserves
   existing allowances and Rails' development localhost default. Repeated calls
   add no duplicates.
5. `TUNNEL_HOST` has no effect on `Rails.application.default_url_options` or on
   any `AppUrl` URL helper.

## Business rules

- **Must** keep the exact-host behavior for `TUNNEL_URL` unchanged; the domain
  allowance is additive and opt-in.
- **Must** accept only `https` Cable origins for the domain; public tunnels
  terminate TLS at the provider.
- **Must** document the variable alongside `TUNNEL_URL` in the README and the
  git-treeline guide, mapping it to Treeline's `{tunnel_host}` token.
- **Should** keep the repository `.treeline.yml` safe for developers without a
  named tunnel, whose token resolves to an empty string.

## Acceptance checks

### agent-loopable

- Unit tests cover unset, valid, and every invalid `TUNNEL_HOST` category with
  safe error messages and no mutation on failure.
- Unit tests cover the host entry, the Cable pattern's accepted and rejected
  origins, idempotence, and untouched URL defaults and public helpers.
- A real Rails boot accepts the domain and immediate subdomains in `Host` and
  `X-Forwarded-Host`, rejects nested subdomains and lookalike domains, and makes
  matching Cable origin decisions.
- The existing suite stays green on the current Rails line; `git diff --check`
  and `specline check .` pass.

### judgeable

- README and guide text make clear when to set `TUNNEL_HOST`, that it is a
  domain rather than a URL, and that it does not replace `TUNNEL_URL`.

### human-gate

- Jonathan authorized implementation; he reviews the contract wording and the
  security scope of a development-only domain wildcard before release.

## Out of scope

The git-treeline `share` hint that recommends `.trycloudflare.com` under a named
domain, and the quick-tunnel fallback while a named tunnel daemon is running,
are tool defects to fix in git-treeline. Version bump and release are a separate
decision.
