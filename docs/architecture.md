# Architecture

`app-url-rails` is a Ruby gem that gives Rails applications one API for their
configured address and an optional externally reachable address. `AppUrl` reads
`Rails.application.default_url_options` and `TUNNEL_URL`; its public helpers fall
back to the configured address when the tunnel override is absent. It does not
infer request hosts or read Action Mailer's separate URL defaults.

The install generator writes development configuration for `DEV_URL` and
`TUNNEL_URL`: route URL defaults, allowed hosts, and Action Cable origins when
Cable is available. The gem currently has no Railtie or boot hook of its own.
The helper and generator are two responsibilities in one package. Gem hardening
and a possible future Rails contribution are separate goals; pursuing the latter
is Jonathan's decision after the gem is sound.

Read `README.md` for the current API, `docs/git-treeline.md` for development
integration context, and `CONTRIBUTING.md` for verification commands. Specs under
`docs/specs/` describe proposed work, not shipped behavior. Existing documentation
stays in place; this adoption does not backfill historical specs.
