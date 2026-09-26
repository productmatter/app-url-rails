# Decisions for the attended build

No unresolved decision blocks implementation. Jonathan authorized the agreed
adjustments and implementation on 2026-09-26.

- Target version: **2.0.0**, with documented breaking changes and a one-time
  manual migration from copied wiring. Publication remains separately authorized.
- Explicit setup works wherever called; the generator installs it in development.
- Rails constructs configured origins; `url_options` remains a passthrough.
- Environment validation raises `AppUrl::ConfigurationError < ArgumentError`;
  Rails retains its `ArgumentError` for invalid configured protocol options.
- Build size is `large`, with a verified baseline and implementation delivered
  as separate reviewable increments.
- Implementation uses the recommended default matrix: **Rails 8.0 and 8.1 ×
  Ruby 3.2 and 3.4**, with exact patch versions recorded in test results. The
  client-inventory question remains available to Jonathan; add older lines only
  if he identifies that need. This is an adopted default, not a claim that he
  supplied an inventory or individually confirmed every version.
