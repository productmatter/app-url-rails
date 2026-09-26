# Recorded verification

Verified on 2026-09-26 with Ruby 3.4.8, Rails 8.1.4, AppUrl 2.0.0 from this
checkout, Puma 8.0.2, and git-treeline 0.58.0. The sample's lockfile records the
resolved dependencies. Addresses and port below belong to this worktree;
Treeline supplies different values for other allocations.

## Generator

The app was created with `rails new`, retaining Action Cable and skipping the
DB, mail, jobs, storage, asset/JavaScript tooling, and deployment scaffolding.
After adding the local path dependency and installing its bundle:

```sh
bin/rails generate app_url:install
```

The first invocation exited zero and added the marker plus setup call inside
Rails' fresh development configure block. A second invocation exited zero,
reported the existing installation, and left `development.rb` unchanged.
A separate reviewer reran that command and compared SHA-256 before and after:

```text
ea4ae0a510074254681935ed3a4e018474b91665fc9dbcc691e4ce413303bf61
```

No app-maintained URL defaults, hosts, or Cable origin allowlists supplement the
generated call. `bundle exec rails zeitwerk:check` also passed.

## Treeline and real network requests

From the repository root:

```sh
gtl setup .
gtl start
# In another terminal:
gtl start --await --await-timeout 30
gtl routes --json
```

Treeline allocated port `3442`, wrote the sample's ignored `.env.local`, installed
its bundle, and started Puma. The running application reported:

```text
DEV_URL         https://app-url-rails-app-url-hardening.prt.dev
TUNNEL_URL      (empty)
AppUrl.base_url https://app-url-rails-app-url-hardening.prt.dev
callback_url    https://app-url-rails-app-url-hardening.prt.dev/callback
```

The public base and callback URLs matched their default counterparts. The
server was restarted after removing scaffold-only fallback configuration,
then verified again using Rails' ordinary generated local development secret.

From `examples/worktree_app`, both commands passed all 17 live checks:

```sh
bundle exec ruby bin/verify
VERIFY_URL=https://app-url-rails-app-url-hardening.prt.dev bundle exec ruby bin/verify
```

These checks prove:

- HTTP responses from the home page, diagnostics, and callback route.
- The loaded gem's source path is this repository.
- The canonical URL and a request-independent Rails route use `DEV_URL`.
- Public helpers and public route options fall back correctly without a tunnel.
- The configured HTTP Host is accepted; unrelated and lookalike hosts return 403.
- Actual WebSocket upgrades, Cable welcome messages, subscriptions, and echoes
  succeed for the canonical origin and that origin with `:3001`.
- Cable rejects unrelated, lookalike, and wrong-scheme origins.

HTTPS/WSS requests used normal certificate verification; it was not disabled.
The supported browser URL above uses port 443. An additional direct router-port
probe to `:3001` was intermittent and timed out on repeat, so direct `:3001`
reachability is not claimed. The same-host `:3001` **origin policy** was verified
through the working canonical connection.

## Repository checks and limits

The existing gem suite passed: **84 runs, 1,970 assertions, zero failures,
errors, or skips**, under `LC_ALL=C` with Ruby 3.4.8. Specline 3.0 validation,
index sync, and whitespace checks passed. Gem packaging uses ordinary
`gem build`: RubyGems 3.x warns about the intentional open-ended Rails
dependencies, while RubyGems 4.0.10 does not. The earlier local strict-build
result did not establish portability of warning behavior between those versions.

This run proves one real Treeline worktree, its generated installation, and
its local HTTPS router. It does not claim a provisioned public tunnel, an
external webhook delivery, a browser automation run, or a second simultaneous
worktree. Optional tunnel wiring is described in the sample README. The gem's
existing integration suite separately covers explicit public URL overrides.
