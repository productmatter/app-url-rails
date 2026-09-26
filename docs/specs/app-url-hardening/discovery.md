# Two separate goals: a sound gem and possible Rails ownership

## Goal 1: make the existing gem dependable

The gem already resolves normal/public addresses and wires development URL
defaults, host authorization, and Cable origins. Those are two responsibilities
in one developer experience, not two products to split apart. The build contract
for spec `app-url-hardening` preserves that product shape while moving the copied
development wiring behind an explicit gem-owned configuration call.

Inspection on 2026-09-26 found:

- A host-only configuration returns an HTTPS `base_url`, while `url_options`
  does not supply a protocol. Rails' effective default depends on its secure
  protocol setting, wired to `force_ssl`; a standalone probe returned HTTP with
  that setting false and HTTPS with it true. The mismatch is configuration-dependent.
- A standalone Action Pack 8.1.3.1 probe rejected explicit empty protocol strings
  and `http::`, while accepting `http:`, `https://`, `http`, and `https`. The gem's
  existing tolerance tests do not establish compatibility with Rails.
- `TUNNEL_URL=localhost:3000` yields `{ host: nil, protocol: "localhost" }`
  from `public_url_options` instead of a useful configuration error.
- A tunnel URL ending in `/prefix` retains that path in `public_base_url` but
  loses it in `public_url_options`.
- The installer skips if either environment variable name appears anywhere in
  the development file, including comments.
- Helper tests substitute a fake application; generator tests primarily inspect
  output text and separately constructed origin regexes, rather than booting an
  installed app and exercising its behavior.
- The documentation's blanket claim that initializers are too late is stronger
  than Rails' boot sequence supports. Ordering before middleware construction is
  the relevant boundary; `after_initialize` is too late.

These are inspection findings and focused Ruby probe results, not a claim that
the existing suite or a multi-version integration matrix has been executed.

## Changes proposed after Fable's review

- Replace copied wiring with `AppUrl.configure_development!(config)` at the same
  explicit config-time location. This keeps the no-Railtie design while allowing
  wiring fixes to ship in the gem. It intentionally adds one public entry point.
- Retain a one-time manual migration for existing generated blocks. A thin call
  simplifies future upgrades; it does not eliminate today's installed legacy code
  or ambiguous custom wiring. Version the installation format, not every release.
- Establish a real-boot harness first, then use it to guard semantic changes and
  command-level failure status. Installer failure/conflict must exit non-zero.
- Follow Rails' effective protocol behavior, including `force_ssl`, rather than
  introducing a fixed HTTP fallback or preserving malformed protocol spellings.
- Validate `public_url` too, while returning valid strings unchanged. It reads
  `TUNNEL_URL` in every environment; its compatibility impact is not dev-only.
- Improve diagnostics without echoing rejected values wholesale. Userinfo is not
  the only place a URL can carry credentials; paths, queries, fragments, and
  malformed inputs also need protection from accidental inclusion in errors.
- Treat version-support narrowing and incompatible 1.0.0 behavior as explicit
  decisions. A minor bump is not automatically appropriate. Prefer maintained
  Rails lines plus justified older compatibility coverage; verify actual pairings.

Jonathan approved implementation on 2026-09-26 after review. The final amendments
remove the silent environment gate, delegate origin construction to Rails, name
`AppUrl::ConfigurationError`, and declare build size `large` (Specline has no
`medium` size). Release and support decisions are in `open-questions.md`; the
build sequence is in `implementation.md`. Rails core work remains deferred.

## Goal 2: explore the same capability inside Rails

This goal is deferred and independently decided by Jonathan after gem hardening.
It is not necessary to make the gem useful, and no forum post, Rails checkout,
pull request, or public communication is authorized by this spec.

The candidate framework home is **Railties**, attached to `Rails.application`.
Railties owns application configuration and boot coordination; the application
already delegates `default_url_options` to its routes. This is a placement
recommendation, not an accepted upstream design.

An illustrative developer-facing shape, **not an existing Rails API**:

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.app_url = ENV["DEV_URL"]
  config.public_app_url = ENV["TUNNEL_URL"]
end
```

```ruby
Rails.application.app_url.base_url
Rails.application.app_url.public_base_url

order_callback_url(**Rails.application.app_url.public_url_options)
```

The application accessor would return an address object with essentially the
gem's existing helper behavior. The proposed config keys hold address strings;
they are distinct from the application accessor's returned object. Apps choose
their environment variable names. Without a public override, public helpers
fall back to the configured address. Existing route defaults remain relevant;
the configuration precedence must be agreed before any framework implementation.

| Responsibility | Candidate framework ownership |
|---|---|
| Declare default/public addresses | `Rails::Application::Configuration` in Railties |
| Resolve addresses and expose the API | An application-owned object in Railties |
| Apply route defaults and development allowed hosts | Application initialization before middleware construction |
| Apply development WebSocket origins | Action Cable's existing engine initialization |

The intended experience is to declare addresses once and have Rails own the
integration. Today the gem copies that wiring; the hardening proposal would move
it behind a gem-owned setup call. Framework ownership is a separate step. It
requires separate decisions about precedence, multi-domain applications,
development-only permissions, protocol semantics, and existing custom settings.
Mailer unification and tenant-domain inference are not assumed features.

If Jonathan elects to pursue this goal, shape a separate spec around the agreed
framework behavior. Start with real application examples and the hardened gem as
evidence, then discuss the proposal in the Rails core forum before investing in
a framework patch. Maintainer interest and eventual acceptance are unknown.

## Sources

- [Rails URL generation](https://api.rubyonrails.org/v8.0/classes/ActionDispatch/Routing/UrlFor.html)
- [Rails protocol normalization](https://github.com/rails/rails/blob/v8.1.0/actionpack/lib/action_dispatch/http/url.rb)
- [Rails secure-protocol configuration](https://github.com/rails/rails/blob/v8.1.0/actionpack/lib/action_dispatch/railtie.rb)
- [Rails maintenance policy](https://rubyonrails.org/maintenance)
- [Rails application ownership and URL defaults](https://github.com/rails/rails/blob/main/railties/lib/rails/application.rb)
- [Middleware construction during initialization](https://github.com/rails/rails/blob/main/railties/lib/rails/application/finisher.rb)
- [Action Cable engine configuration](https://github.com/rails/rails/blob/main/actioncable/lib/action_cable/engine.rb)
- [Rails contribution instructions](https://github.com/rails/rails/blob/main/CONTRIBUTING.md)

Sources were reviewed on 2026-09-26. Rails `main` is moving context, not a claim
about every supported released version; recheck against the implementation's
actual test matrix and any future framework target.
