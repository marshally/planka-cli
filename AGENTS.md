# Agent instructions

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo
root), use CodeGraph before searching or reading code to understand or locate it.
Use `codegraph_explore` when available, or `codegraph explore "<symbols or question>"`
from the shell. If no `.codegraph/` directory exists, skip CodeGraph; indexing is
the user's decision.
<!-- CODEGRAPH_END -->

## Engineering and review

Before designing, implementing, refactoring, or reviewing code, read
[CODING_STANDARDS.md](CODING_STANDARDS.md). During review, apply its criteria to
changed code and affected interfaces; identify ownership and dependency problems
as well as correctness defects. Report Standards and Spec findings separately.

For CLI behavior changes, read [STYLEGUIDE.md](STYLEGUIDE.md) and the relevant
slice in [the implementation handoff](docs/CLI_REDESIGN_IMPLEMENTATION.md).
For workflow changes or loading/extraction decisions, read
[the workflow module guide](docs/WORKFLOW_MODULE.md).

## Dependency versions and documentation

Before using or changing dependency behavior, read `Gemfile.lock` for the exact
resolved gem versions and `BUNDLED WITH` version. Use that Bundler version and
run repository checks through `bundle exec`. Keep dependency upgrades explicit
and within the requested scope; preserve the lockfile during unrelated work.
The lockfile governs the development bundle, while the gemspec and CI define the
supported dependency and Ruby ranges.

Use Context7 for version-sensitive dependency documentation. Resolve the relevant
library, select documentation matching the locked version when available, and
include that version in the query. Confirm the result actually applies to that
version; a version in the query alone is not evidence. If Context7 is unavailable
or lacks matching documentation, inspect the installed locked gem or official
versioned documentation/source and state the verification limit. Avoid relying
on current-version examples for APIs absent from the locked release.

## Agent skills

### Issue tracker

Track work in GitHub Issues for `marshally/planka-cli` using `gh`.
See [issue-tracker.md](docs/agents/issue-tracker.md).

### Triage labels

Use the five default triage-role labels.
See [triage-labels.md](docs/agents/triage-labels.md).

### Domain docs

Use a single root context with ADRs under `docs/adr/`, created as needed.
Before codebase exploration, follow [domain.md](docs/agents/domain.md).
