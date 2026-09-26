# Suggested implementation sequence

This is build guidance for spec `app-url-hardening`. The contract and acceptance
criteria live in `spec.md`; this note adds no independent scope or authorization.

Jonathan authorized this implementation on 2026-09-26, targeting a documented
2.0.0 breaking release. Agree on the version matrix before matrix-dependent work.
Review and commit the green harness baseline before runtime/generator changes;
then deliver the implementation and migration documentation as a second increment.
Separate pull requests are optional and publication is not authorized.

## 1. Establish the real-boot baseline

Before runtime/generator edits, add a minimal fixture application that boots
using the existing installer output and ordinary gem loading. Run each environment
scenario in an isolated subprocess, with variables set before Rails evaluates
its environment file. Avoid databases, bound ports, and real tunnels.

Exercise generated URLs and requests through the actual host middleware. Exercise
Cable's origin decision when Cable is loaded, not just equality of configuration
values. Include an application without Cable. Record passing current behavior;
known defects can have targeted reproductions until their fixes are introduced.
Do not change a failing regression into a passing characterization claim.

## 2. Centralize setup without changing unrelated behavior

Introduce the gem-owned entry point and make new installations call it:

```ruby
# Inside config/environments/development.rb's configure block
AppUrl.configure_development!(config)
```

Add an installation-format marker alongside the call. Version the marker when
that format changes, not when the gem ships a new release. Validate inputs before
applying configuration, keep repeated calls idempotent, and verify early loading.
The existing generator timing remains explicit; no Railtie is required. Do not
add a Rails.env gate: explicit invocation performs setup wherever the app calls it.

Document the one-time manual replacement of legacy generated wiring. Preserve
custom configuration and fail non-zero when the installer cannot establish a
safe current installation. Do not build a Ruby-source migration engine.

## 3. Apply URL correctness changes against that baseline

Keep `url_options` a passthrough. Delegate origin construction to Rails with
only host/protocol/port options, including its effective `force_ssl` behavior.
Do not forward path/query/userinfo/only_path options or duplicate the protocol
normalizer. Replace the empty and
`http::` tolerance tests with rejection coverage. Keep environment-origin parsing
strict and shared inside the gem, and validate `public_url` while preserving a
valid string's original spelling. Use `AppUrl::ConfigurationError < ArgumentError`
for environment validation; let Rails reject configured protocol errors with its
own `ArgumentError` rather than broadly catching unrelated failures.

Errors should name the setting and a concrete reason, for example
"TUNNEL_URL must include an http:// or https:// scheme". A safe reconstructed
origin is useful when available; raw rejected values may contain credentials in
components other than userinfo. Avoid surfacing unsanitized parser exceptions.

## 4. Verify compatibility and document migration

Use the agreed matrix with explicit per-Rails dependency constraints (per-line
Gemfiles are one option) and compatible Ruby/tooling combinations, then record
results for each entry.
Update examples, migration instructions, and release notes to match the tested
contract. Building and reviewing the changes does not authorize publication.
