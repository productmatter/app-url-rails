---
slug: worktree-sample
type: feature
status: building
decider: jonathan
created: 2026-09-26
build: attended
blast_radius: low
size: small
---

# Prove AppUrl in a running Treeline worktree

## Intent

Developers need a runnable example showing that a worktree's allocated address
reaches Rails through the install generator and the current gem. Jonathan
authorized building this sample on 2026-09-26. Appetite: one small Rails app and
repeatable live verification, using this checkout as its gem dependency.

## Non-goals

- Changing the gem's runtime contract or supported Rails versions.
- Adding databases, authentication, a JavaScript build, or a production deployment.
- Publishing a tunnel, changing global Treeline settings, or releasing the gem.

## Behavior

1. A generated Rails app in `examples/worktree_app` loads `app-url-rails` from
   this repository. The actual install generator adds development configuration;
   a second invocation succeeds without changing it.
2. The repository's `.treeline.yml` allocates a port, writes development URL
   variables into the sample's ignored env file, and starts the sample. The app
   loads that file before Rails evaluates its environment configuration.
3. A small page displays the configured application and public URLs and uses a
   real Action Cable connection. A diagnostic endpoint exposes only the finite
   URL/version fields needed to verify the example.
4. Live checks exercise HTTP through the allocated address, named route
   generation, host authorization, and accepted/rejected Cable origins. Without
   a tunnel, public helpers fall back to the application address. Documentation
   distinguishes that proof from external tunnel reachability.

## Business rules

- **Must** use the actual local gem and generator, without copying its wiring
  into app code or manually allowing hosts to mask an installation failure.
- **Must** keep generated env files, credentials, logs, and runtime files out of Git.
- **Must** document setup, verification, and stopping the server. Treeline is
  the featured automation example; AppUrl still accepts variables from any source.
- **Should** keep the sample small enough to understand without reading the gem.

## Acceptance checks

### agent-loopable

- The app boots with its path dependency and the generated setup call.
- Fresh installation and unchanged repeat installation are recorded.
- Treeline allocates this worktree and a real HTTP request returns matching
  application/default route/public fallback addresses.
- Real WebSocket connections accept the configured origin and reject an
  unrelated origin; an unrelated HTTP Host is rejected.
- Sample checks and the existing gem suite pass; `git diff --check` and
  Specline validation pass.

### judgeable

- The page and instructions make the relationship between allocated variables,
  gem wiring, and application URL usage clear without unnecessary infrastructure.

### human-gate

- Jonathan authorized implementation; he reviews the runnable result.

## Out of scope

Live public tunnel provisioning and multi-worktree orchestration beyond this
sample's setup are deferred. They are not required to verify the local handoff.
