## State

building
Implementation and verification complete on `feature/tunnel-host`; ready for
Jonathan's review. Version bump and release are separate decisions.

## Done

- Traced the motivating change (truherd/wildlife_platform#706) to a missing gem
  affordance: git-treeline's share and router proxies forward the public host
  in `X-Forwarded-Host`, Rails checks it against `config.hosts`, and only the
  exact `TUNNEL_URL` host was allowed.
- Confirmed git-treeline supplies `{tunnel_host}` for exactly this purpose and
  recommends a domain wildcard in its own Rails hint.
- Baseline before changes: 84 runs, 1,970 assertions, zero failures on Rails 8.1
  / Ruby 3.4.8 under `LC_ALL=C`.
- Added `TUNNEL_HOST` to `AppUrl.configure_development!`: bare-hostname
  validation with safe errors, `.<domain>` host allowance, one `https`
  any-subdomain any-port Cable origin pattern, idempotent, validated before any
  mutation alongside `DEV_URL` and `TUNNEL_URL`.
- Unit coverage: twelve invalid categories with sentinel-safe messages and no
  mutation; accepted and rejected Cable origins; untouched URL defaults and
  public helpers; idempotence; configuration without Action Cable.
- Real-boot coverage: direct and `X-Forwarded-Host` requests under the domain
  return 200 while lookalike domains return 403; Cable accepts `https` on the
  domain and subdomains and rejects `http` and lookalikes; repeated setup adds
  no duplicates; an invalid `TUNNEL_HOST` aborts before any mutation.
- Documented the variable in the README (configuration table, per-session
  tunnel hosts section) and the git-treeline guide (contract table, `.treeline.yml`
  mapping, forwarded-host note, troubleshooting), and mapped it in this
  repository's `.treeline.yml`.
- Final suite: 91 runs, 2,377 assertions, zero failures/errors/skips under
  `LC_ALL=C` (Rails 8.1 / Ruby 3.4.8); unit tests also green under
  `LC_ALL=en_US.UTF-8`. `git diff --check` clean. Specline reports no errors;
  its two warnings (missing Goal in an older spec, canon pin 3.0.0 vs tool 3.1.0)
  predate this work.

## In progress

- Jonathan's review of the contract wording and the development-only domain
  wildcard scope.

## Dead ends

- Accepting a bare suffix in `TUNNEL_URL`: every public helper would return a
  non-URL, and the 2.0 validator rejects it at boot by design.

## Corrections

- Under a C locale, `ENV` strings are binary and `valid_encoding?` is always
  true, so the malformed-bytes guard checked the value as UTF-8 explicitly.
  Caught by running the suite under `LC_ALL=C`.
- In `RAILS_ENV=test`, a forwarded host under the domain still returns 403
  because Rails allows loopback `Host` values by default only in development;
  the real-boot assertion distinguishes the two environments.
