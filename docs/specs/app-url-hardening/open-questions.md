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
- Jonathan requested retaining Rails 7 compatibility. The matrix is **Rails
  7.0, 7.1, 7.2, 8.0, and 8.1 × Ruby 3.2 and 3.4**, superseding the initial
  Rails 8-only default. Runtime dependencies permit Rails 7.0+ without an upper
  cap based solely on the tested matrix. Exact patch versions are recorded with
  test results; Ruby 3.2 remains the minimum.
