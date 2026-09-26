## State

building
Implementation and adversarial-review corrections are complete; ready for
Jonathan's review and acceptance. Publication and a Rails proposal remain
separate decisions.

## Done

- Renamed the worktree branch to `feature/app-url-hardening` before implementation.
- Locked the agreed review amendments into the Specline 3.0.0 contract.
- Selected a 2.0.0 release target and explicit Rails 8.0/8.1 × Ruby 3.2/3.4 matrix.
- Added and independently reran the real-boot harness before runtime edits: eight
  URL/Cable scenarios, whole suite 50 runs / 204 assertions / zero failures.
- Resolved all four matrix bundles: Rails 8.0.5.1 and 8.1.4 on Ruby 3.2.2 and 3.4.8.
- Implemented gem-owned setup, shared safe environment validation, Rails origin
  construction, and a marked installer with explicit manual migration failures.
- Documented the 2.0.0 breaking changes, migration, timing, and support range.
- Independently reviewed the implementation and fixed inherited development
  ports in public route generation; added a real Rails regression.
- Verified manual legacy replacement, public access without installation in the
  test environment, and all required boot/configuration scenarios.
- Reran the complete suite independently in every matrix entry under `LC_ALL=C`;
  each passed with 84 runs, 1,970 assertions, zero failures/errors/skips. The manual
  migration check also passed under `LC_ALL=en_US.UTF-8` (1 run, 41 assertions).
- Strict gem build passed for 2.0.0. Specline 3.0.0 validation has no findings,
  index sync is current, and `git diff --check` is clean.

## In progress

- Awaiting Jonathan's review of the implemented behavior and evidence.

## Last green checkpoint

review-corrections-20260926 — complete suite under `LC_ALL=C`:

| Ruby | Rails / Action Cable / Action Mailer | Runs | Assertions | Result |
| --- | --- | --- | --- | --- |
| 3.2.2 | 8.0.5.1 | 84 | 1,970 | Passed |
| 3.4.8 | 8.0.5.1 | 84 | 1,970 | Passed |
| 3.2.2 | 8.1.4 | 84 | 1,970 | Passed |
| 3.4.8 | 8.1.4 | 84 | 1,970 | Passed |

Command for each entry:
`LC_ALL=C RBENV_VERSION=<ruby> BUNDLE_GEMFILE=gemfiles/rails_<major>_<minor>.gemfile rbenv exec bundle exec rake test`.

Baseline preserved in commit `8bb1858`, before runtime/generator changes:
`RBENV_VERSION=3.4.8 rbenv exec bundle exec rake test` — 50 runs, 204 assertions,
zero failures/errors/skips on Rails 8.1.3.1.

Build: `RBENV_VERSION=3.4.8 rbenv exec gem build app-url-rails.gemspec --strict`.
Specline checks used the locally bundled CLI via Node because the installed
wrapper requires unavailable `npx`: `check . --format json` and `sync . --check`.

## Dead ends

- None.

## Corrections

- B1: fixture reads explicitly use UTF-8; CI runs the matrix under `LC_ALL=C`.
  The original 68-run green results depended on a UTF-8 locale and did not prove
  portability to C-locale shells.
- B2: declared Action Pack and Railties runtime dependencies for Rails 8.0/8.1.
  An isolated install of the built gem loaded and generated a public origin with
  no Bundler or Action Cable installed in its gem directory (Ruby 3.4.8, Action
  Pack/Railties 8.1.4). The check set `GEM_HOME` and `GEM_PATH` to an empty temporary
  directory, cleared `RUBYOPT` and Bundler settings, installed the built `.gem`,
  then required `app-url-rails` and called `public_base_url` in a new process.
- B3: retained Rails' localhost Cable fallback for unset origins in development;
  real boots verify explicit empty/custom lists and other environments keep
  their own policies.
- S1–S4/S7: concrete protocol outputs, entry-point exit status and helper calls,
  specific error reasons and sentinel checks for both environment settings,
  untouched configuration without installation, and actual Rails application
  objects now replace the weak assertions and global accessor overrides.
  Real Cable decisions stay in integration tests; unit tests check configuration.
- S5–S6: added `bin/rails generate` discovery, exact command exits, untouched other
  environment files, additional configure/legacy shapes, lookalike host checks,
  SSL/explicit protocol cases, repeated route output, uncaught invalid-DEV boot
  failure, later settings, and real Action Mailer defaults. Direct public-helper
  access outside development covers every invalid-input category in one boot.
- Matrix lockfiles remain untracked intentionally: recorded exact versions are
  point-in-time evidence; CI resolves current compatible patches on each line.
  Generator formatting strictness remains intentional. Local Bundler warnings
  concern pre-existing tooling and are outside the gem change.
- Documented configuration-time protocol defaults, mailer assignment ordering,
  and Rails host rewriting through `subdomain:`/`domain:` route options.
- Follow Rails' effective protocol default including force_ssl, rather than assuming HTTP — provable — reviewer
- Replace copied configuration logic with a gem-owned explicit entry point — judgeable — reviewer
- Remove silent environment gating and name the configuration exception — judgeable — reviewer
- Include the effective tunnel port in public URL options to override inherited route defaults — provable — independent implementation review
