# Documentation conventions

`specline.yml` is the source of truth for the Specline 3.0.0 pin and tier 0
adoption. Tier 0 introduces draft specs and structural validation; it does not
introduce a CI workflow, unattended build runner, or model routing configuration.

Jonathan Simmons (`jonathan`) is the decider. No deputy is designated. Specs are
attended and remain drafts until Jonathan authorizes their implementation.
Writing a spec does not authorize a build, release, push, or external proposal.

Use the sections and acceptance partitions in the pinned canon. Keep unresolved
product decisions in `open-questions.md`, and distinguish recommended defaults
from approved choices. Keep exploratory Rails integration material separate from
the gem's build contract. Preserve existing code conventions and documentation
locations unless the task requires a change.

Run `specline check .` to validate structure. Generated directory READMEs belong
to `specline sync`; edit authored documents instead. The canonical methodology is
available through `specline spec` and https://specline.dev/spec.md; verify its
version against the repository pin before following a newer revision.
