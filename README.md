# planka-cli

Ruby CLI and library for Planka board workflows, extracted from Lucenta.
Requires Ruby 3.2 or newer. The redesigned administration interface targets
Planka 2.0.0 and higher; Planka 1.x is outside its scope. Version-specific
capabilities require API verification as implementation proceeds.
Board workflows use the conventions
`ready-for-agent`, `in-progress`, `done`, `Acceptance criteria`, `Blocked by`,
`feature:<slug>` and `effort:<slug>`. Linked tasks represent blocking edges.

## Install locally

```sh
bundle install
make ci
gem install ./pkg/planka-cli-0.1.0.gem
planka --help
```

Use `planka <command>` as the primary interface. The gem also installs a
`planka-<command>` executable for each operation so existing scripts can call
commands directly. Both forms accept the same arguments and flags; their help
and diagnostics use the primary command name. The Node MCP launcher and any
1Password wrapper remain in Lucenta; they are repository integrations rather
than Ruby gem commands.

Run `planka --help` (or `planka -h`) to list commands, and
`planka <command> --help` (or `-h`) for that command's usage and options.
Help works without credentials. Use `planka --version` for the gem version.

## Usage — planned interface

The target administration interface uses kubectl-style verb/resource commands:

```text
planka <verb> <resource> [reference] [flags]
planka workflow <operation> [arguments] [flags]
```

**The invocations below describe the proposed interface, which is not yet
implemented.** See [STYLEGUIDE.md](STYLEGUIDE.md) for the contract and migration
mapping. See [Current interface](#current-interface) for working commands and
[Workflow examples](#workflow-examples) for an end-to-end publishing sequence.
See the [implementation handoff](docs/CLI_REDESIGN_IMPLEMENTATION.md) for the
first implementation task, acceptance criteria, and settled decisions.

Uppercase references such as `BOARD`, `LIST`, and `CARD` are placeholders for
IDs, supported resource URLs, or exact names within a known parent scope.
Singular and plural resource spellings are aliases. Each project supplies its
own environment settings; missing required variables fail before network access.
Explicit parent flags select scope; ambiguous names are rejected.

### Read resources

```sh
planka get projects
planka get boards --project PROJECT
planka get lists --board BOARD
planka get cards --board BOARD
planka get cards --list LIST
planka get card CARD
planka get labels --board BOARD
planka get comments --card CARD
planka describe board BOARD
planka describe card CARD
```

`get` lists a collection or reads one resource concisely. `describe` includes
related information. Both are read-only.

Collection reads return all scoped results by default, following supported API
pages internally. Use `--limit N` to cap results; JSON `meta.complete` identifies
complete versus truncated results. A page-fetch failure exits nonzero and retains
collected results with an error rather than reporting successful completion.

```sh
planka get cards --board BOARD --limit 20 -o json
```

Combine collection filters with AND; repeated labels or members must all match.
`--name` matches exactly, and the limit applies after filtering:

```sh
planka get cards --board BOARD \
  --label enhancement \
  --label feature:search \
  --member USER \
  --name "Fix login" \
  --limit 20
```

This selects up to 20 cards named `Fix login` with both labels and the specified
member. Filters are available only on commands where they are meaningful; there
is no general selector language or filter-based bulk mutation interface.

### Create, update, move, and delete resources

```sh
planka create list --board BOARD --name "Ready" --type active --position 65536
planka create card --list LIST --name "Fix login" --description-file description.md
planka update card CARD --name "Fix session expiry" --description-file revised.md
planka move card CARD --list LIST --position 65536
planka delete card CARD
planka create label --board BOARD --name enhancement --color berry-red
planka create task-list --card CARD --name "Acceptance criteria" --position 65536
planka update task-list TASK_LIST --name "Verification"
planka create comment --card CARD --text "Ready for review"
planka delete comment COMMENT
```

Updates change only supplied fields. New resources and moved cards append to
their destination unless `--position` is supplied. `--description-file -` reads
stdin. Deletes require an explicit target; supported combinations of verbs and
resources depend on the Planka API.

An explicit `delete RESOURCE REF` executes without prompts or a `--yes` flag,
with identical behavior in terminals and scripts. Deletion follows the server's
native behavior and restrictions. The CLI issues only the target deletion, with
no recursive client-side deletes or `--cascade` flag. See the
[API deletion evidence](docs/CLI_REDESIGN_IMPLEMENTATION.md#upstream-deletion-evidence)
for resource-specific effects.

### Attach and detach relationships

```sh
planka add label LABEL --card CARD
planka remove label LABEL --card CARD
planka add member USER --card CARD
planka remove member USER --card CARD
```

`add` and `remove` change relationships without creating or deleting the label
or user. An already-satisfied relationship succeeds without another change.

### Specs, tickets, and agent workflows

```sh
planka workflow guide
planka workflow create spec --list LIST --name "Search" --description-file spec.md
planka workflow create ticket --list LIST --name "Index documents" \
  --criteria-file criteria.json --description-file ticket.md
planka workflow resume ticket CARD --criteria-file criteria.json
planka workflow next --board BOARD
planka workflow next --board BOARD --label feature:search
planka workflow next --board BOARD --label effort:search
planka workflow claim CARD
planka workflow claim-status
planka workflow branch-name CARD
planka workflow pending-criteria CARD
planka workflow add blocker BLOCKER --card BLOCKED
planka workflow add blocker BLOCKER_ONE BLOCKER_TWO --card BLOCKED
planka workflow remove blocker BLOCKER --card BLOCKED
planka workflow complete-specs
```

These operations use the list, label, acceptance-criteria, and blocker
conventions described in the style guide. `--criteria-file` accepts a JSON array
of strings or `-` for stdin. Resume an interrupted ticket instead of creating a
duplicate. `claim` adds membership and moves a card into progress;
`claim-status` only reports existing claims. `complete-specs` comments and moves
eligible specs to done.

### Environment and authentication

Each project supplies its own connection, credential, and scope environment.
There are no saved contexts or configuration files. Missing or empty required
variables cause an immediate error before network access. Help, version, and the
built-in guide work without connection settings.

Use the same `PLANKA_*` names with project-specific values, as listed under
[Current interface](#current-interface). Required scope depends on the command
and its explicit references. Each API command signs in using
`PLANKA_AGENT_EMAIL` and `PLANKA_AGENT_PASSWORD`, holds the token in memory, and
attempts sign-out when finished. There are no saved credentials, authentication
prompts, `auth login/logout` commands, or externally supplied-token mode.
Authentication is scoped to the server selected by the project's environment.

### Output, help, and version

```sh
planka get card CARD -o json
planka get cards --board BOARD --output json
planka workflow next --board BOARD -o json
planka --help
planka create --help
planka create card --help
planka workflow --help
planka --version
```

Human-readable output is the default. JSON mode emits one structured document
on stdout; diagnostics go to stderr and failures exit nonzero. Help and version
require no credentials or network. Unknown write outcomes must be reconciled
before retrying; incomplete workflows retain recovery state in JSON output.

## Current interface

The installed CLI currently uses the flat commands below. Run
`planka <command> --help` for full arguments and options. Each operation also
has a direct `planka-<command>` executable.

These flat commands and direct executables are deprecated in the redesign
contract and retained indefinitely with their existing arguments, behavior, JSON
shapes, and exit codes. No removal is scheduled; a later sweep belongs to a
separate track of work. Deprecation notices belong in documentation, help, and
release notes, with no automatic runtime warnings. The planned canonical
replacements above are not yet implemented.

### Configuration

Supply resolved credentials in the process environment:

| Variable | Used for |
| --- | --- |
| `PLANKA_BASE_URL` | Instance URL, e.g. `https://planka.example.com` |
| `PLANKA_AGENT_EMAIL` | Login email or username |
| `PLANKA_AGENT_PASSWORD` | Login password |
| `PLANKA_BOARD_ID` | Board used by `next-card` only |
| `PLANKA_BRANCH_PREFIX` | Optional preview/DNS prefix, e.g. `lucenta-`; default empty |

Card commands derive the board from the card. `loop-lock` and `spec-sweep`
inspect all boards visible to the signed-in user. No command reads `.mcp.json`,
looks in another checkout for secrets, or invokes 1Password automatically.
For `op://` references, launch the command through your own `op run` setup.

### Working commands

All commands support `--output json`; the default is human-readable output.
Diagnostics go to stderr and failures exit nonzero. Cards accept numeric IDs or
card URLs. List and label names must match exactly within their board; ambiguous
names require IDs.

| Invocation | Purpose |
| --- | --- |
| `planka prime` | Print built-in agent guidance without credentials or network. |
| `planka snapshot [--board ID] [--list ID_OR_NAME]` | Read a board or one list's cards. |
| `planka show CARD` | Read a card's description, labels, tasks, blockers, and comments. |
| `planka labels [--board ID]` | Read board labels. |
| `planka create-list --name NAME [--board ID]` | Create a board column. |
| `planka create-spec --list ID_OR_NAME --title TITLE` | Create a spec; optionally supply `--description-file`. |
| `planka create-ticket --list ID_OR_NAME --title TITLE --criteria-file FILE` | Create a ticket with acceptance criteria. |
| `planka update-card CARD [--title TITLE] [--description-file FILE]` | Update a card. |
| `planka move-card CARD --list ID_OR_NAME` | Move a card. |
| `planka create-label --name NAME [--board ID] [--color COLOR]` | Create or reuse a label. |
| `planka apply-label CARD --label ID_OR_NAME` | Attach a label. |
| `planka create-task-list CARD --name NAME` | Create a task list. |
| `planka rename-task-list --id TASK_LIST_ID --name NAME` | Rename a task list. |
| `planka next-card [FEATURE_OR_EFFORT_LABEL]` | Select takeable work or report an effort frontier. |
| `planka branch-name CARD` | Generate a branch slug. |
| `planka unticked CARD` | Read incomplete acceptance criteria. |
| `planka loop-lock` | Report the signed-in user's open claim without a PR handoff. |
| `planka claim CARD` | Add membership and move a card into progress. |
| `planka comment CARD TEXT` | Post a comment. |
| `planka link BLOCKED BLOCKER [BLOCKER...]` | Record blockers. |
| `planka spec-sweep` | Comment and move finished specs to done. |

`next-card` uses the authenticated `gh` CLI when a blocker has a GitHub PR
handoff. `Branch:` and `PR:` lines in comments determine parent branches.
`prime --output json` returns the guide as `{"instructions":"..."}`.

## Workflow examples

These examples use the current interface. Before publishing work, create the
conventional `ready-for-agent`, `in-progress`, and `done` columns. A spec is a
project card without acceptance criteria; a ticket has one `Acceptance criteria`
task list, which lets the picker distinguish them.

Descriptions and criteria accept file paths or `-` for stdin, preserving
newlines, quotes, and Unicode. Criteria files contain a JSON array of strings.

### Publish a dependency-ordered batch

A dependency-ordered batch is a scripted sequence of these primitives: create
each blocker before the cards it blocks, append new work below the queue
(`--position` is optional; work lands at the bottom by default), label the cards,
`link` dependents to their blockers, then `move-card` the spec into `in-progress`.
For example:

```sh
feature=$(planka create-label --name feature:work-next --output json | jq -r .label.id)
spec=$(planka create-spec --list ready-for-agent --title 'Spec: work-next' \
  --description-file spec.md --output json | jq -r .card.id)
first=$(planka create-ticket --list ready-for-agent --title 'Ticket 1' \
  --criteria-file t1.json --output json | jq -r .card.id)
second=$(planka create-ticket --list ready-for-agent --title 'Ticket 2' \
  --criteria-file t2.json --output json | jq -r .card.id)
for c in "$spec" "$first" "$second"; do planka apply-label "$c" --label "$feature"; done
planka link "$second" "$first"
planka move-card "$spec" --list in-progress
```

### Recover an interrupted write

Do not retry a create when its outcome is unknown. Read the board back first;
JSON failure output retains created resources and reconciliation instructions.
If a ticket was created but some criteria are missing, resume it with:

```sh
planka create-ticket --card CARD --criteria-file criteria.json --output json
```

This adds only missing criteria. `claim`, `link`, and `apply-label` may be safely
repeated, and `create-label` reuses an existing label with the same name.

## Library

```ruby
require "planka-cli"

Planka::Client.session do |client|
  board = Planka::Board.new(client.board(ENV.fetch("PLANKA_BOARD_ID")),
    base_url: ENV.fetch("PLANKA_BASE_URL"))
  puts board.cards.first
end
```

`Board` also accepts a captured API `included` payload. Supply `base_url:` when
using multiple instances in one process. `BranchName.for(card, prefix: "app-")`
accepts a per-call prefix. The library preserves the `Planka` namespace.

## Development and extraction boundary

`make test` runs the captured-board tests and local HTTP command tests.
`make build` builds the gem; `make ci` runs both. CI covers Ruby 3.2, 3.4 and 4.0.
The tests do not contact a live Planka instance. API endpoints and payload shapes
are inherited from Lucenta, including its captured Community board fixture;
compatibility with other Planka releases has not been established.

Lucenta continues using its original library and 1Password integrations.
Switching it to this gem is a separate consumer change once a repository or
release is available to CI. No release license has been selected; choose one
before publishing the gem.
