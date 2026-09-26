## State

building
Implementation and automated verification are complete; ready for Jonathan's
review and acceptance. Publication and a Rails proposal remain separate decisions.

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
- Ran the complete suite independently in every matrix entry; each passed with
  68 runs, 1,058 assertions, zero failures/errors/skips.
- Strict gem build passed for 2.0.0. Specline 3.0.0 validation has no findings,
  index sync is current, and `git diff --check` is clean.

## In progress

- Awaiting Jonathan's review of the implemented behavior and evidence.

## Last green checkpoint

implementation-20260926 — complete suite:

| Ruby | Rails / Action Cable | Runs | Assertions | Result |
| --- | --- | --- | --- | --- |
| 3.2.2 | 8.0.5.1 | 68 | 1,058 | Passed |
| 3.4.8 | 8.0.5.1 | 68 | 1,058 | Passed |
| 3.2.2 | 8.1.4 | 68 | 1,058 | Passed |
| 3.4.8 | 8.1.4 | 68 | 1,058 | Passed |

Command for each entry:
`RBENV_VERSION=<ruby> BUNDLE_GEMFILE=gemfiles/rails_<major>_<minor>.gemfile rbenv exec bundle exec rake test`.

Baseline preserved in commit `8bb1858`, before runtime/generator changes:
`RBENV_VERSION=3.4.8 rbenv exec bundle exec rake test` — 50 runs, 204 assertions,
zero failures/errors/skips on Rails 8.1.3.1.

Build: `RBENV_VERSION=3.4.8 rbenv exec gem build app-url-rails.gemspec --strict`.
Specline checks used the locally bundled CLI via Node because the installed
wrapper requires unavailable `npx`: `check . --format json` and `sync . --check`.

## Dead ends

- None.

## Corrections

- Follow Rails' effective protocol default including force_ssl, rather than assuming HTTP — provable — reviewer
- Replace copied configuration logic with a gem-owned explicit entry point — judgeable — reviewer
- Remove silent environment gating and name the configuration exception — judgeable — reviewer
- Include the effective tunnel port in public URL options to override inherited route defaults — provable — independent implementation review
