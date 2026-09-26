## State

building
Real-boot baseline is green; runtime and generator implementation can now begin.

## Done

- Renamed the worktree branch to `feature/app-url-hardening` before implementation.
- Locked the agreed review amendments into the Specline 3.0.0 contract.
- Selected a 2.0.0 release target and explicit Rails 8.0/8.1 × Ruby 3.2/3.4 matrix.
- Added and independently reran the real-boot harness before runtime edits: eight
  URL/Cable scenarios, whole suite 50 runs / 204 assertions / zero failures.
- Resolved all four matrix bundles: Rails 8.0.5.1 and 8.1.4 on Ruby 3.2.2 and 3.4.8.

## In progress

- Runtime URL validation/setup and generator migration behavior.

## Last green checkpoint

baseline-20260926 — `RBENV_VERSION=3.4.8 rbenv exec bundle exec rake test`: 50 runs,
204 assertions, zero failures/errors/skips on Rails 8.1.3.1; runtime/generator unchanged.

## Dead ends

- None.

## Corrections

- Follow Rails' effective protocol default including force_ssl, rather than assuming HTTP — provable — reviewer
- Replace copied configuration logic with a gem-owned explicit entry point — judgeable — reviewer
- Remove silent environment gating and name the configuration exception — judgeable — reviewer
