---
slug: app-url-hardening
type: feature
status: building
decider: jonathan
created: 2026-09-26
build: attended
blast_radius: medium
size: large
---

# Make AppUrl dependable and keep development wiring in the gem

## Intent

Developers should configure application addresses once and receive wiring fixes
through gem upgrades, without maintaining copied implementation code in every
app. Address representations must agree with Rails, invalid configuration must
fail clearly, and installation must produce working Rails configuration.

Appetite: one review sitting for a gem-owned development configuration entry
point, URL correctness, reliable installation/migration, and real-boot evidence.
The gem remains one package with its existing default/public distinction. This
was approved for implementation by Jonathan on 2026-09-26. Release target:
2.0.0; publishing remains a separate decision.

## Goal

A fresh or explicitly migrated application uses one gem-owned development setup
call, and real Rails tests prove consistent URL results, actionable validation
failures, and reliable installation without changing developer-owned wiring.

## Non-goals

- Splitting the gem, renaming existing helpers, or adding a Railtie/automatic hook.
- Unifying mailer defaults, request hosts, or tenant domains.
- Supporting environment URL path prefixes, changing cookies, or changing the
  existing development Cable policy for different ports on the same scheme/host.
- Automatically rewriting legacy/custom wiring, adding a verbose generator mode,
  or introducing a general configuration framework.
- Building a Rails core API, preparing a submission, publishing, or releasing.

## Behavior

1. **Gem-owned development setup.** The proposed public entry point is
   `AppUrl.configure_development!(config)`, called explicitly from the app's
   development configure block. The gem owns parsing and wiring; generated code
   contains a call and an installation-format marker, not a copied algorithm.
   Both environment inputs are validated before any configuration is changed.
   Repeating the call with unchanged inputs does not duplicate hosts/origins.
   The explicit call performs the same setup in any Rails environment; the
   generator installs it only in development. Requiring the gem alone does not
   configure an application.
2. **Preserved integration behavior.** With `DEV_URL`, the setup applies its
   scheme, host, and effective port to route URL defaults, preserving unrelated
   options. A default port replaces any stale non-default port. Both supplied
   hosts are allowed, existing allowed hosts/origins are preserved, and Cable
   receives the existing scheme/host policy allowing different ports. Apps
   without Cable work. With neither variable set, setup makes no changes. The
   call takes effect at its position in the configure block: earlier address
   defaults are overridden by `DEV_URL`; later explicit app settings can override
   it. It neither changes mailer defaults nor derives values from requests.
3. **Consistent configured addresses.** For host/protocol/port configuration,
   `base_url` agrees with actual Rails URL generation on scheme, host, and
   effective port. An omitted protocol follows Rails' effective default,
   including HTTPS when Rails is configured accordingly through `force_ssl`;
   it must not be hardcoded to HTTP. Accepted protocol spellings follow Rails,
   including `http`, `https`, `http:`, and `https://`. Explicit empty strings and
   `http::` raise instead of being repaired. `url_options` remains a passthrough
   to application defaults and does not normalize, copy, or mutate that hash.
   Without a host, `host` and `base_url` retain their `nil` behavior.
4. **Validated environment addresses.** `DEV_URL` and `TUNNEL_URL` accept absolute
   HTTP(S) addresses with a host, optional integer port from 1 through 65535, and
   optional trailing slash. Scheme-less values, missing hosts, unsupported
   schemes, userinfo, non-root paths, queries, fragments, invalid ports, and
   whitespace-only values raise `AppUrl::ConfigurationError < ArgumentError`.
   All gem-owned environment validation uses that exception. Rails errors for
   configured protocol options remain `ArgumentError`. Unset/empty values mean
   no override. Setup
   validates at boot. Independently of installation or Rails environment, all
   public helpers (`public_url`, `public_host`, `public_url_options`, and
   `public_base_url`) reject invalid tunnel values on access. `public_url` returns
   the original valid string, or `nil` without an override; it does not fall back.
5. **Consistent public addresses and useful errors.** The public override affects
   only public helpers. `public_base_url` and `public_url_options` represent the
   same normalized origin; a trailing slash or explicit default port does not
   change that origin. Public URL options include the effective tunnel port so
   Rails route generation cannot inherit an unrelated application port.
   IPv6 and non-default ports work. The other public helpers
   retain their existing fallback when the override is absent. Errors name the
   setting, the specific failure, and the expected shape. They may include a
   safely reconstructed scheme/host/port, but never echo userinfo, path, query,
   fragment, or unparseable raw input that could contain a credential.
6. **Reliable installation and migration.** Fresh installation adds one setup
   call and a marker identifying the installation format, not the gem release.
   A recognized current installation is an unchanged success. Comment-only
   mentions of environment variables or the method name do not count as setup.
   Legacy copied blocks get a clear one-time migration instruction and a non-zero
   exit, without modification. Partial/custom wiring, ambiguous or unsupported
   installation formats, missing files, and unsupported configure-block shapes
   likewise fail non-zero with an actionable diagnostic and no partial write.
   Success and verified no-op both exit zero. The documented manual migration
   replaces only the old generated wiring; subsequent implementation fixes arrive
   through gem upgrades without replacing the call while its format is supported.
7. **Accurate compatibility guidance.** Documentation distinguishes current from
   proposed behavior and explains explicit production protocols, supported inputs,
   precedence, errors, migration, and restarting after environment changes. It
   explains the before-middleware timing boundary rather than claiming every
   initializer is too late. Release notes identify changed protocol output,
   rejected inputs (including `public_url`), normalized base URLs, and any changed
   support range. No release is described as automatically backward-compatible.

## Business rules

- **Must** first establish a passing real-boot characterization baseline against
  current behavior, before modifying runtime or generator behavior. Preserve that
  evidence, then add regressions for proposed behavior; do not normalize existing
  defects into permanent expectations. See `implementation.md` for sequencing.
- **Must** preserve existing helper names, request independence, missing-value
  fallbacks, and the default/public distinction, except for the explicit changes
  above. One new public development setup method is intentional.
- **Must** validate all environment inputs before applying setup mutations and
  preserve developer-owned configuration when installation is ambiguous.
- **Must** retain on-demand tunnel reads in all environments. This does not
  promise live updates of boot-time host/Cable settings or tunnel reachability.
- **Must** use actual Rails behavior as the protocol reference and keep configured
  protocol options distinct from stricter HTTP(S) environment URL inputs.
- **Must** test actual generated calls and booted apps, including command exit
  statuses and failure messages; copied test implementations are insufficient.
- **Must** ship these compatibility changes under the agreed 2.0.0 version and
  verify the concrete support matrix below. Publishing still requires Jonathan's
  explicit instruction.
- **Should** delegate configured origin construction to Rails URL generation
  with only host/protocol/port options. Do not emulate protocol normalization or
  pass unrelated path, query, credential, or `only_path` options to origin
  construction. The public `url_options` passthrough remains unchanged.
- **Should** share validation inside the gem rather than repeat it in generated
  code. Keep the new entry point small and the wiring readable in gem source.

## Assumptions

- The 2.0 matrix is Rails 8.0 and 8.1, each on Ruby 3.2 and 3.4, with matching
  Action Cable dependencies and per-line Gemfiles. This adopts the recommended
  maintained-line default during the authorized build; client inventory can
  extend it by agreement. The previous unverified Rails 7.0+ claim is replaced
  by the explicit tested lines. Record exact patch versions with test results.
- Rails owns effective protocol defaults and initialization order. Verify with
  `force_ssl` both enabled and disabled on the agreed matrix. If behavior differs
  by version, bring the compatibility choice back rather than invent workarounds.
- The setup method is available when the generated environment configuration runs;
  verify the normal gem loading path during a real boot, not just in direct tests.
- Existing proxy workflows rely on Cable's digit-port matching, including the
  tested `99999` case. Preserve that policy separately from environment input
  validation, which accepts ports only through 65535. Existing host/origin
  permissions remain intact; rejection tests must use unrelated hosts/origins
  that the fixture did not already allow.
- The setup call is installed only in development but has no environment gate.
  Explicit invocation configures the supplied app in any environment. Public URL
  helpers are not development-only, so their validation changes require compatibility treatment.
- Rails ownership in `discovery.md` remains exploratory and independently decided.

## Critical files

- `lib/app_url.rb` and `lib/generators/app_url/install_generator.rb`
- `test/app_url_test.rb`, `test/generators/app_url/install_generator_test.rb`,
  and `test/require_test.rb`
- `README.md`, `docs/git-treeline.md`, and `CONTRIBUTING.md`
- `Gemfile`, `Rakefile`, `app-url-rails.gemspec`, and `.github/workflows/main.yml`

## Acceptance checks

### agent-loopable

- A recorded real-boot baseline predates runtime/generator changes. New integration
  scenarios run in separate processes with environment set before configuration,
  without a database, bound port, or live tunnel. They cover neither variable,
  each alone, both together, and Cable present/absent.
- Integration checks exercise route generation, host authorization, and actual
  Cable origin decisions. They prove preserved custom allowances, rejection of
  unrelated/lookalike hosts and wrong schemes, stale-port replacement, repeat-call
  idempotence, validation before any mutation, and equivalent explicit setup in
  another environment.
- URL checks compare AppUrl with real Rails helpers under both `force_ssl`
  settings. They cover omitted/explicit/invalid protocols, accepted spellings,
  passthrough options, default/non-default ports, IPv6, missing hosts, public
  fallbacks, and unchanged valid spelling from `public_url`.
- Every public helper rejects every invalid tunnel category in Behavior 4,
  including direct use without installation and outside development. Setup also
  rejects invalid `DEV_URL`. Tests assert `AppUrl::ConfigurationError` for
  environment inputs and Rails `ArgumentError` for invalid configured protocols.
  Error tests prove a specific useful reason is shown
  and sentinel credentials in userinfo, path, query, fragment, or malformed input
  are not echoed.
- Generator subprocess tests assert content and exit status for clean install,
  current no-op, comment-only mentions, legacy/partial/custom/unknown wiring,
  missing files, and unsupported configure blocks. Failure cases leave files
  unchanged. A documented manual legacy-to-call migration boots successfully.
- The agreed Ruby/Rails matrix, dependency resolution, and per-entry results are
  recorded; all tests pass in each entry — run: `bundle exec rake test`
- The gem remains buildable — run: `gem build app-url-rails.gemspec --strict`
- The documentation structure remains valid — run: `specline check .`

### judgeable

- Against **Behavior 1–2 and 6** and **Business rules**, review confirms the gem
  owns the wiring, migration is bounded and explicit, configuration is preserved,
  and tests exercise the installed call after real boot rather than copies.
- Against **Behavior 3–5 and 7**, review confirms Rails-consistent protocol
  semantics, validation across every public helper, useful safe diagnostics,
  and disclosure of all compatibility changes.
- Against **Assumptions** and **Non-goals**, review confirms support claims fit
  the recorded matrix and no automatic hooks or framework contribution slipped in.

### human-gate

- Jonathan approved the revised contract and implementation on 2026-09-26.
  The support matrix follows the recommended default, subject to any client
  compatibility requirements raised during this attended build.
- Jonathan accepts the resulting gem behavior and evidence. Whether to pursue
  Rails or publish a release remains a separate decision.

## Out of scope / deferred

Rails integration stays in `discovery.md`, without a build commitment. Path-prefix
support, mailer unification, tenant/domain overrides, a Railtie, automatic legacy
rewriting, and a verbose generator mode remain deferred. `implementation.md`
records a suggested test-first sequence, not additional product scope.
