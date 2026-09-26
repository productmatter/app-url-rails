# One worktree, one Rails URL

This small Rails app uses **the gem in this checkout**. Treeline supplies its
address; the generated AppUrl call connects Rails URL defaults, allowed hosts,
and Action Cable. The home page shows the result and opens a real WebSocket.

## Run it

Use Ruby 3.4.8 (see `.ruby-version`), Bundler, and git-treeline. Rails 8.1 is the
example's Rails version; the gem itself supports Rails 7.0+. The sample's
committed lockfile records its verified dependency versions.

From the **repository root**, with your Ruby version manager active:

```sh
gtl setup .       # allocates this worktree, writes .env.local, installs gems
gtl start         # keep this terminal open
```

In another terminal at the repository root:

```sh
gtl start --await --await-timeout 30
gtl routes
```

Open the router URL shown by `gtl routes`. This configuration uses Treeline's
HTTPS router, so it must already be running. For a machine without the router,
change `DEV_URL` in `.treeline.yml` to `"http://localhost:{port}"`, run
`gtl env sync`, and restart the server. The same gem setup works either way.

The Rails install generator has already been run. To see that reinstalling is
an unchanged success:

```sh
cd examples/worktree_app
bundle exec rails generate app_url:install
```

On shells that do not activate rbenv automatically, select Ruby before running
these commands, for example:

```sh
export PATH="$(RBENV_VERSION=3.4.8 rbenv prefix)/bin:/opt/homebrew/bin:$PATH"
```

## What is connected

1. Root `.treeline.yml` writes `PORT` and `DEV_URL` into this app's ignored
   `.env.local`. Treeline also supplies those values to its server process.
2. `dotenv-rails` loads the same file for direct Rails commands before the
   development configuration runs.
3. The generator adds its marker and `AppUrl.configure_development!(config)`
   in `config/environments/development.rb`. The gem owns all the wiring.
4. The page uses `AppUrl.base_url` and `AppUrl.public_base_url`; the diagnostic
   endpoint checks named Rails route generation too. Action Cable uses the
   configured origin without an app-maintained host/origin allowlist.

The app has no database, external services, or JavaScript build. Its Gemfile
uses `path: "../.."`, so gem edits in this worktree are the code it runs.

## Verify a running instance

From this directory:

```sh
bundle exec ruby bin/verify
```

To include the HTTPS router in the check, pass its URL:

```sh
VERIFY_URL=https://your-worktree.prt.dev bundle exec ruby bin/verify
```

TLS verification stays enabled. If Ruby does not use your system's trusted
Treeline CA, supply its certificate path with `SSL_CERT_FILE`.

The verifier checks real HTTP responses, URL generation, host rejection, and
WebSocket acceptance/rejection. See [verification.md](verification.md) for the
recorded Treeline/router run and generator evidence.

## Optional public URL

`TUNNEL_URL` is deliberately empty by default. Public helpers then fall back to
`DEV_URL`. To use a public tunnel, first configure and verify one, set the root
`.treeline.yml` mapping to `TUNNEL_URL: "{tunnel_url}"`, then run `gtl env sync`
and restart Rails. Treeline can interpolate a tunnel address without checking
its reachability; an address alone is not proof of a working public tunnel.

The install generator requires no further changes when either URL changes.

## Stop it

Run `gtl stop` from the repository root, or press Ctrl+C in the `gtl start`
terminal. Restart after changing the environment or the gem's boot-time wiring.
Environment files, logs, runtime files, and generated secrets are ignored.
This app is a development example, not a production deployment template.
