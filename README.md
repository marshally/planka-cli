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

The gem has not been published. Its executable names include `planka` and
all eight existing `planka-*` commands. `bin/planka-op` and the Node MCP
launcher remain in Lucenta; they are repository integrations rather than Ruby
gem commands.

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
