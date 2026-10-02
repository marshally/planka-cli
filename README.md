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

```sh
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
