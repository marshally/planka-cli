# planka-cli

Ruby CLI and library for Planka board workflows, extracted from Lucenta.
Requires Ruby 3.2 or newer. Board workflows use the conventions
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

## Usage

The target administration interface uses kubectl-style verb/resource commands:

```text
planka <verb> <resource> [reference] [flags]
planka workflow <operation> [arguments] [flags]
planka config <operation> [flags]
planka auth <operation> [flags]
```

**The invocations below describe the proposed interface, which is not yet
implemented.** See [STYLEGUIDE.md](STYLEGUIDE.md) for the contract and migration
mapping. The [Commands](#commands) and
[Publishing and reading specs and tickets](#publishing-and-reading-specs-and-tickets)
sections document the currently available commands.

Uppercase references such as `BOARD`, `LIST`, and `CARD` are placeholders for
IDs, supported resource URLs, or exact names within a known parent scope.
Singular and plural resource spellings are aliases. Explicit flags override
environment settings and saved context defaults; ambiguous names are rejected.

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

### Contexts and authentication

```sh
planka config set-context home --server https://planka.example.com \
  --project PROJECT --board BOARD
planka config get-contexts
planka config use-context home
planka get cards --context home
planka --context home get cards
planka auth login
planka auth status
planka auth logout
```

Contexts select a server and default scope. `--context` overrides the selected
context for one invocation. Authentication is scoped to the selected server.

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

## Configure

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

## Commands

Run `planka prime` at the start of an agent session or after context compaction
to print a succinct guide to connection settings, JSON output, ticket workflows,
publishing, and failed-write recovery. It uses built-in instructions and works
without credentials, a checkout, or a live Planka instance. `planka-prime` is the
equivalent direct executable. `planka prime --output json` returns the guide as
`{"instructions":"..."}`.

```sh
planka prime                      # concise agent workflow instructions
planka next-card                  # top unclaimed, unblocked ticket by position
planka next-card feature:search   # earliest takeable ticket for a feature
planka next-card effort:search    # wayfinder map and frontier
planka branch-name CARD           # branch slug; fits 63 chars including prefix
planka unticked CARD              # incomplete acceptance criteria
planka loop-lock                  # signed-in user's open claim without PR handoff
planka claim CARD                 # add membership and move to in-progress
planka comment CARD 'Branch: card/example'
planka link BLOCKED BLOCKER [BLOCKER...]
planka spec-sweep                 # comment and move finished specs to done
```

Cards may be numeric ids or card URLs. `claim`, `comment`, `link` and
`spec-sweep` write to Planka. `claim` and `link` may be safely repeated.
`next-card` uses the authenticated `gh` CLI when a blocker has a GitHub PR
handoff. `Branch:` and `PR:` lines in comments determine parent branches.

Every command prints a concise human-readable result by default. Add
`--output json` for a single structured JSON document intended for agents and
scripts. The flag works with both command styles:

```sh
planka show CARD --output json
planka-show CARD --output json
```

Diagnostics go to stderr and failures exit nonzero. Partial creates and writes
whose outcome is unknown retain recovery state and reconciliation instructions
in JSON mode.

## Publishing and reading specs and tickets

These commands create, read back and verify specs and tickets. Their default
output is formatted for a person; use `--output json` for automation. `--help`
needs no credentials.

```sh
planka snapshot [--board ID] [--list ID|NAME]   # whole board, or one list's cards
planka show CARD                                 # one card: description, labels, tasks, blockers, comments
planka create-list   --name NAME [--board ID] [--type active|closed] [--position N]
planka create-spec   --list ID|NAME --title T [--description-file F|-] [--position N]
planka create-ticket --list ID|NAME --title T --criteria-file F [--description-file F|-] [--position N]
planka create-ticket --card CARD --criteria-file F        # resume a ticket whose creation failed
planka update-card   CARD [--title T] [--description-file F|-]
planka move-card     CARD --list ID|NAME [--position N]
planka labels        [--board ID]
planka create-label  --name NAME [--board ID] [--color COLOR]
planka apply-label   CARD --label ID|NAME
planka create-task-list CARD --name NAME [--position N]
planka rename-task-list --id TASK_LIST_ID --name NAME
```

`create-list` adds a column to a board (a fresh board has none); create the
conventional `ready-for-agent`, `in-progress` and `done` columns before adding
cards. A spec is a project card with no acceptance criteria; a ticket is a
project card with one `Acceptance criteria` task list, so the picker keeps them
apart. Lists
and labels may be given by id or exact name; an ambiguous name is rejected rather
than guessed. A board can carry two labels with the same name (for example two
`enhancement` labels); apply those by id, since the name is ambiguous. `--description-file` and `--criteria-file` take a path or `-` for
stdin, so descriptions and criteria keep their newlines, quotes and Unicode
without shell quoting. `--criteria-file` is a JSON array of strings.

`create-spec`, `create-ticket`, `create-label`, `apply-label` and `move-card`
write to Planka; `snapshot`, `show` and `labels` are read-only. A create is never
retried once its outcome is unknown: in JSON mode, a timeout returns what it
created and a `reconcile` hint rather than risking a duplicate. `create-label`
reuses a label with
the same name, `apply-label` is safe to repeat, and `create-ticket --card` fills
only the criteria still missing, so an interrupted ticket is finished, not
duplicated.

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
