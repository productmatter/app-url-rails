# Architecture

`app-url-rails` is a Ruby gem that gives Rails applications one API for their
configured address and an optional externally reachable address. `AppUrl` reads
`Rails.application.default_url_options` and `TUNNEL_URL`. Public host, options,
and base-URL helpers fall back to the configured address when the override is
absent; `public_url` returns the validated original tunnel string or `nil`.
It does not infer request hosts or read Action Mailer's separate URL defaults.

The install generator writes a versioned marker and an explicit
`AppUrl.configure_development!(config)` call. That method validates `DEV_URL` and
`TUNNEL_URL` before updating route URL defaults, allowed hosts, and Action Cable
origins when Cable is available. Legacy copied wiring requires a one-time manual
migration. The gem has no Railtie or automatic boot hook.
The helper and generator are two responsibilities in one package. Gem hardening
and a possible future Rails contribution are separate goals; pursuing the latter
is Jonathan's decision after the gem is sound.

Read `README.md` for the current API, `docs/git-treeline.md` for development
integration context, and `CONTRIBUTING.md` for verification commands. Specs under
`docs/specs/` describe proposed work, not shipped behavior. Existing documentation
stays in place; this adoption does not backfill historical specs.
