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
  Cable origin pattern for the domain and its immediate subdomains on any port,
  idempotent, validated before any mutation alongside `DEV_URL` and `TUNNEL_URL`.
- Unit coverage: twelve invalid categories with sentinel-safe messages and no
  mutation; accepted and rejected Cable origins; untouched URL defaults and
  public helpers; idempotence; configuration without Action Cable.
- Real-boot coverage: direct and `X-Forwarded-Host` requests to the domain or its
  immediate subdomains return 200. Nested subdomains and lookalike domains
  return 403. Cable accepts matching `https` origins; repeated setup adds
  no duplicates; an invalid `TUNNEL_HOST` aborts before any mutation.
- Documented the variable in the README (configuration table, per-session
  tunnel hosts section) and the git-treeline guide (contract table, `.treeline.yml`
  mapping, forwarded-host note, troubleshooting), and mapped it in this
  repository's `.treeline.yml`.
- Independent adversarial review of the final diff: no material defects;
  Rails' one-label rule confirmed identical across actionpack 7.0 through 8.1.
  Its findings are recorded under Corrections.
- Final suite: full ten-entry matrix (Rails 7.0/7.1/7.2/8.0/8.1 × Ruby
  3.2.2/3.4.8) under `LC_ALL=C`, each green; see the last green checkpoint.
  Unit tests also green under `LC_ALL=en_US.UTF-8`. `git diff --check` clean.
  Specline reports no errors; its two warnings (missing Goal in an older spec,
  canon pin 3.0.0 vs tool 3.1.0) predate this work.

## In progress

- Pull request and merge on green CI, authorized by Jonathan on 2026-11-21.

## Last green checkpoint

tunnel-host-20261121: complete suite under `LC_ALL=C`, each entry 91 runs,
2,432 assertions, zero failures/errors/skips, on Ruby 3.2.2 and 3.4.8 × Rails
7.0 (7.0.10), 7.1, 7.2, 8.0, and 8.1 (8.1.4.1). Command per entry:
`LC_ALL=C RBENV_VERSION=<ruby> BUNDLE_GEMFILE=gemfiles/rails_<major>_<minor>.gemfile rbenv exec bundle exec rake test`.
`gem build app-url-rails.gemspec` succeeds.

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
- Rails' leading-dot host entry allows the apex and exactly one subdomain
  label. The first Cable pattern accepted any depth, so host authorization and
  Cable disagreed on nested hosts; narrowed to one label and documented as
  "immediate subdomains" (found in a second-agent review).
- The hostname check used `/i`, whose Unicode case folding accepted non-ASCII
  lookalikes such as the Kelvin sign under a UTF-8 locale; replaced with
  explicit `A-Z` and added the case to the invalid set (adversarial review).
- README example switched from a real tunnel domain to `tunnels.example`, with
  an explicit warning that sibling subdomains are same-site for Cable.
