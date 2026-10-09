# planka-cli

Ruby CLI and library for Planka board workflows, extracted from Lucenta.
Requires Ruby 3.2 or newer. The redesigned resource interface targets
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

Resource commands work directly with Planka resources and relationships.
Workflow commands apply project conventions, such as queue selection, acceptance
criteria, and branch naming. These categories do not imply administrator
privileges; operations use the authenticated user's Planka permissions.

The target resource interface uses kubectl-style verb/resource commands:

```text
planka <verb> <resource> [reference] [flags]
planka workflow <operation> [arguments] [flags]
```

**The invocations below describe the target interface. Only `planka describe
card CARD`, `planka describe board BOARD`, `planka workflow pending-criteria CARD`,
`planka workflow branch-name CARD`, `planka workflow claim-status`,
`planka workflow guide`, `planka workflow next`, `planka workflow claim CARD`,
card-scoped `get members`, `get member`, `add member`, `remove member`,
`get cards`, `get card`, `create card`, `update card`, `move card`, `delete card`,
`get lists`, `get list`, `create list`, `update list`, `delete list`,
`get task-lists`, `get task-list`, `create task-list`, `update task-list`,
`delete task-list`, native `get labels`, `get label`, `create label`, `update label`,
`delete label`, card-scoped `add label`/`remove label`,
`get comments`, `get comment`, `create comment`, `update comment`, `delete comment`,
`get boards`, `get board`, `create board`, `update board`, `delete board`,
`get projects`, `get project`, `create project`, `update project`, `delete project`,
`planka workflow create spec`, `planka workflow resume ticket`,
and their root/group/leaf help are
implemented so far; the other
redesigned commands remain planned.** See [STYLEGUIDE.md](STYLEGUIDE.md) for the contract and migration
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
planka get users --board BOARD --username marshall
planka get user me
planka get projects
planka get boards --project PROJECT
planka get lists --board BOARD
planka get cards --board BOARD
planka get cards --list LIST
planka get card CARD
planka get labels --board BOARD
planka get comments --card CARD
planka get tasks --card CARD --completed false
planka get task TASK -o json
planka get members --board BOARD
planka get member USER --board BOARD
planka get members --card CARD
planka get member USER --card CARD
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
planka create project --name "Delivery" --description "Release planning"
planka update project PROJECT --description-file description.md
planka update project PROJECT --clear-description
planka create board --project PROJECT --name "Development"
planka update board BOARD --name "Delivery"
planka create list --board BOARD --name "Ready" --type active --position 65536
planka update list LIST --name "Finished" --type closed
planka create card --list LIST --name "Fix login" --description-file description.md
planka update card CARD --name "Fix session expiry" --description-file revised.md
planka move card CARD --list LIST --position 65536
planka delete card CARD
planka create label --board BOARD --name enhancement --color berry-red
planka update member USER --board BOARD --role editor
planka create task-list --card CARD --name "Acceptance criteria" --position 65536
planka update task-list TASK_LIST --name "Verification"
planka create task --task-list TASK_LIST --name "Verify login"
planka create task --task-list TASK_LIST --linked-card CARD
planka update task TASK --completed true
planka move task TASK --task-list TASK_LIST
planka delete task TASK
planka create comment --card CARD --text "Ready for review"
planka delete comment COMMENT --card CARD
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
planka add member USER --board BOARD --role viewer --can-comment true
planka remove member USER --board BOARD
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

### Canonical boards

```sh
planka get boards --project PROJECT [--name NAME] [--limit N] -o json
planka get board BOARD [--project PROJECT] -o json
planka create board --project PROJECT --name NAME [--position N] -o json
planka update board BOARD [--project PROJECT] [--name NAME] [--position N] -o json
planka delete board BOARD [--project PROJECT] -o json
```

`board`/`boards` are aliases. BOARD accepts an ID, same-instance `/boards/ID`
URL, or exact name within explicit `--project`. PROJECT accepts an ID or
same-instance `/projects/ID` URL, not a project name. An explicit project must
match the board's actual parent; it never relocates the board. `PLANKA_BOARD_ID`
is unused. Unknown resources fail; ambiguous names report candidate IDs and
exit 1. Explicit parent mismatches exit 2.

Reads return concise board objects: `id`, `projectId`, `name`, `position`,
nullable ISO timestamps `createdAt`/`updatedAt`, and `url`. Individual `data`
is an object with empty `meta`; collection `data` is always an array.
`get boards` requires explicit project scope and reads every board visible to
the caller from one project response, without pagination. Results are sorted
by position then numeric ID. Exact `--name` filtering precedes positive `--limit`;
unsupported label/member filters and filters on individual reads are errors.
`meta.complete` is true only when every matching board is returned. Truncation
is successful; a failed or malformed read exits 1 with validated matching
records retained and `complete: false`. A failed project fetch returns `[]`.
Completeness describes visible boards, not hidden boards or a snapshot across
concurrent changes.

Creation always creates, even if the name exists. Names must be nonblank and at
most 128 UTF-16 units; positions must be finite and nonnegative. The default
position is the highest project board position plus 65536, or 65536 for an empty
project. Planka may normalize positions and renumber neighboring boards.
Updates require name, position, or both; send only supplied changed fields;
and preserve omitted fields. Neither field has clearing semantics. Identical
updates are a no-op. Project relocation, imports, display settings, card defaults,
and subscriptions remain outside these commands.

Native creation gives the creator editor membership and creates archive/trash
lists; the CLI makes no additional membership/list writes. Deletion makes one
target DELETE without prompts, `--yes`, or `--cascade`. Planka removes the board's
lists, cards, labels, memberships, and related data; the CLI makes no child
deletes. Native create/update/delete require project-manager permission. Native
read visibility includes managers and board members, with the server's additional
administrator visibility for projects without an owner manager.

Successful mutations return the resulting board, with `deleted: true` on delete,
and `meta.changed: true`; identical updates return the observed board and false.
Rejected writes return false and observed data (a rejected create has only
`projectId` known, other fields null). Unknown writes return `unknown_outcome`,
`changed: null`, and observed fields with requested changed fields null; delete
adds `deleted: null`. Before any successful observation, failure data is null.
Unknown creates retain a numeric returned ID absent from the observed project,
with its URL, when available; other new fields remain null. IDs are never invented.
An existing board ID returned by creation cannot confirm a new board.

Recovery uses `readback-boards` with `resources: [{type: "project", id: PROJECT}]`
when no board ID is known: inspect `get boards --project PROJECT` before deciding
whether to retry. With a board ID, `readback-board` includes both project and board
references: inspect `get board BOARD` or the project collection. No write is
automatically retried. Cleanup errors preserve the operation's result.

Human reads show `NAME (ID) on project PROJECT_ID: URL`, one line per board,
or `No boards.`; limited collections include a truncation notice. Mutations
prefix the same fields with `Created board`, `Updated board`, or `Deleted board`.
All JSON responses use `{data, meta, error}`. Success exits 0, local input 2,
operational/API failures 1. `describe board` and legacy `snapshot` retain their
existing detailed outputs. [Community v2.2.1 source evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#board-api-evidence) are recorded separately
from local HTTP and installed-package checks; no live write acceptance is claimed.

### Canonical projects

```sh
planka get projects --name Product --limit 10 -o json
planka get project PROJECT
planka create project --name Product --type private --description-file project.md
planka update project PROJECT --name Roadmap --clear-description
planka delete project PROJECT
```

Project commands use the selected instance and signed-in user's access, without
board defaults or parent flags. `PROJECT` accepts a numeric ID, same-instance
`/projects/ID` URL, or exact name among accessible projects on that instance.
Missing names/IDs fail; ambiguous names report candidate IDs and exit 1. Numeric
references remain IDs. Singular/plural spellings are aliases for every verb.

`get projects` returns all accessible projects from one Community v2.2.1 response,
without pagination. It preserves native response order, which groups manager/
board-member projects and additional shared projects visible to administrators;
it is not a globally sorted or transactionally consistent snapshot. Exact `--name`
filtering precedes a positive `--limit`. Labels, members, and parent filters are
unsupported, and collection flags are rejected for individual reads. Malformed
records or retrieval failures preserve matching valid records read so far, set
`meta.complete: false`, and exit 1. Limited successful results exit 0.

Creation always creates, even when a name exists. `--type private|shared` defaults
to private and is creation-only. Native creation requires an administrator or
`projectOwner` account; it creates the caller's project-manager relationship,
and makes that relationship the owner for private projects. The CLI sends one
POST and no manager writes. Basic updates and deletion require native project
manager permission. Reads allow managers, project board members, and, for shared
projects, administrators. Native access denial may return 404 (`not_found`).

Names must be nonblank and at most 128 UTF-16 code units. Descriptions accept
mutually exclusive `--description TEXT` or `--description-file FILE`, where `-`
reads stdin; input is nonblank UTF-8 text at most 1024 UTF-16 code units. Unicode,
quotes, and newlines are preserved without truncation. An omitted creation
description leaves native null. Updates additionally accept mutually exclusive
`--clear-description` to send null, preserve omitted fields, and reject empty
updates. Identical values skip PATCH. File reading and local validation happen
before authentication. Type/ownership transfers, backgrounds, visibility,
favorites, and project-manager commands remain outside this interface.

Deletion sends one native target DELETE. Planka rejects projects that still have
boards; the client makes no child deletions or cleanup writes. On successful
empty-project deletion, Planka removes its manager/favorite relationships,
backgrounds, and custom-field settings. There are no prompts or cascade flags.

All commands use `{data, meta, error}`. Reads return the following object, or an
array of these objects for collections; unrelated native fields are omitted:

```json
{"id":"123","name":"Product","description":null,"type":"private",
 "ownerProjectManagerId":"456","createdAt":null,"updatedAt":null,
 "url":"https://planka.example/projects/123"}
```

`type` derives from native `ownerProjectManagerId` (private when non-null, shared
otherwise); the owner ID is a relationship ID, not a user ID. Timestamps and
description are nullable. Successful individual reads use `meta: {}`; collections
use `meta.complete`. Human reads print name, ID, and URL, with `No projects.` for
an empty collection and a truncation notice when limited. Human mutations prefix
the same fields with Created/Updated/Deleted project.

Mutations return the resulting project, with `deleted: true` for deletion, and
`meta.changed: true`; identical updates return false. A rejected write returns
observed state and false (creation has null fields). Unknown/malformed writes
return null changed status, observed values for unchanged fields, and null for
uncertain changed fields (`deleted: null` for uncertain deletion). Uncertain
creation retains a valid returned ID when available, but leaves unconfirmed
fields/URL null. No write is retried. Recovery is `readback-project` with
`resources: [{"type":"project","id":"123"}]` for a known identity, otherwise
`readback-projects` with an empty resource array. Use `get project PROJECT` or
`get projects` to reconcile before retrying. API/unknown failures exit 1, local
input exits 2, success exits 0; cleanup failures preserve the primary result.

Evidence is pinned to official Community v2.2.1 source and local HTTP/package
checks. No live project writes or cross-version compatibility are claimed; see
[project API evidence](docs/CLI_REDESIGN_IMPLEMENTATION.md#project-api-evidence).
No legacy project commands exist; all flat/direct commands remain unchanged.

### Canonical cards

```sh
planka get cards --board BOARD [--name NAME] [--label LABEL]... [--member USER]... [--limit N] -o json
planka get cards --list LIST [--board BOARD] [filters] -o json
planka get card CARD -o json
planka create card --list LIST --name NAME [--description-file FILE|-] [--position N] -o json
planka update card CARD [--name NAME] [--description-file FILE|-] -o json
planka move card CARD --list LIST [--position N] -o json
planka delete card CARD -o json
```

`card` and `cards` are aliases. CARD is an ID, same-instance URL, or exact name
with `--board BOARD` or `PLANKA_BOARD_ID`; explicit card IDs/URLs determine their
own board and ignore the default board, and an explicit `--board` must match.
Card names resolve on the board's active/closed lists. LIST is an ID,
same-instance URL, or exact name on `--board BOARD` or `PLANKA_BOARD_ID`; a list
ID alone finds its own board for active/closed lists (Planka has no individual
read for archive/trash lists, so those need `--board`). A list on another board
than `--board` is `invalid_input`. Ambiguous names report candidate IDs.

Card `data` contains `id`, `name`, nullable `description`, `type`, `boardId`,
`listId`, nullable `position` (null in archive/trash lists), and nullable
`createdAt`/`updatedAt`. Individual reads return an object with empty `meta`.

`get cards` requires `--board` or `--list` and returns an array with
`meta.complete`. It reads cards in the board's active and closed lists, in board
list order with cards by position, from the single native board read. Cards in
archive and trash lists are not included, and `--list` naming an archive or trash
list is `invalid_input`. Exact `--name`, every repeated `--label` (board label ID or
name), and every repeated `--member` (card member, by board user ID or name)
must all match before a positive `--limit`; filters and limits are rejected with
a CARD. `complete` describes matching cards. An unknown label or member is
`not_found`. A malformed read exits 1 with the matching cards read so far and
`complete: false`.
Reads make no resource writes.

`create card` always creates a native card, even when the name exists, using the
board's `defaultCardType`; it adds no criteria, claims, blockers, or members.
It appends after the highest position in an active/closed list unless
`--position N` gives a finite nonnegative native ordering value, which Planka may
normalize. Archive/trash lists take no position, and `--position` there is
`invalid_input`. `update card` changes only supplied fields, sends only values
that differ, and requires at least one of `--name` or `--description-file`;
identical values are a no-op. Names are nonempty and at most 1024 characters;
descriptions are nonempty and at most 1048576 characters, read before any
request, and `-` reads stdin. Empty description input is rejected; clearing a
description is not supported. `move card` resolves LIST on the card's own board,
appends to active/closed lists unless `--position` is given, sends a null
position to archive/trash lists, and treats the current list without
`--position` as a no-op. It changes only list and position. `delete card` issues
one native deletion of an explicit target without prompts; Planka deletes the
card's task lists, tasks, attachments, comments, memberships, label assignments,
and subscriptions, and clears other tasks' links to it without deleting those
cards.

Mutation `data` is the resulting card; delete adds `deleted: true`.
`meta.changed` is true, false for a no-op, or null when unknown. A rejected write
keeps the unchanged card (`changed: false`) with the native failure code. An
unknown or malformed write response returns `error.code: unknown_outcome`,
`changed: null`, and marks requested fields null (`deleted: null` for delete).
Unknown creates preserve a valid numeric returned ID only when it was absent
from the observed cards; other returned fields remain unconfirmed. With such an
ID, inspect `get card CARD` using `readback-card` recovery. Otherwise the ID stays
null with `readback-cards` recovery for the list: inspect `get cards --list LIST`
for active/closed lists before retrying, or inspect archive/trash in Planka.
Other mutations
report `readback-card`: inspect `get card CARD`. No request is retried
automatically.

Human reads print `NAME (CARD_ID) in list LIST_ID` per card, or `No cards.`;
limited output adds a truncation notice. Mutations print `Created card`,
`Updated card`, `Moved card`, or `Deleted card ... from list LIST_ID`. Success
exits 0, local input 2, other failures 1. Writes require native board editor
permission. See the [source evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-tenth-slice-cards).

### Canonical lists

```sh
planka get lists --board BOARD [--name NAME] [--limit N] -o json
planka get list LIST [--board BOARD] -o json
planka create list --board BOARD --name NAME [--type active|closed] [--position N] -o json
planka update list LIST [--board BOARD] [--name NAME] [--color COLOR | --clear-color] [--position N] [--type active|closed] -o json
planka delete list LIST [--board BOARD] -o json
```

`list` and `lists` are aliases. LIST is an ID, same-instance URL, or exact name
with `--board BOARD` or `PLANKA_BOARD_ID`; explicit list IDs/URLs determine their
own board and ignore the default board, and an explicit `--board` must match.
Planka reads only active and closed lists individually, so an archive or trash
list ID without `--board` is `not_found`; with `--board` it resolves on the
board. Ambiguous names report candidate IDs.

List `data` contains `id`, nullable `name` (archive lists may be unnamed),
`type` (`active`, `closed`, `archive`, or `trash`), nullable `color`, `boardId`,
nullable `position`, and nullable `createdAt`/`updatedAt`. Individual reads
return an object with empty `meta`.

`get lists` requires an explicit `--board`; `PLANKA_BOARD_ID` is not a collection
scope. It returns every list on the board, of every native type, from the single
native board read without paging: active and closed lists by position, then
archive and trash lists. Exact `--name` matches before a positive `--limit`;
`--label` and `--member` are unsupported. `complete` describes matching lists,
and a malformed read exits 1 with `complete: false`. Reads make no resource writes.

`create list` always creates a native list, even when the name exists. `--board`
is required, `--type` is `active` (default) or `closed`, and archive/trash
system lists cannot be created. It appends after the board's active and closed
lists, ignoring archive and trash, unless `--position N` gives a finite
nonnegative native ordering value. Planka may renumber list positions. Names are
nonempty and at most 128 characters. Colors cannot be set on creation.

`update list` changes only supplied fields, sends only values that differ, and
requires at least one of `--name`, `--color`, `--clear-color`, `--position`, or
`--type`; identical values are a no-op. `--color` takes one of `berry-red`,
`pumpkin-orange`, `lagoon-blue`, `pink-tulip`, `light-mud`, `orange-peel`,
`bright-moss`, `antique-blue`, `dark-granite`, or `turquoise-sea`;
`--clear-color` sends an explicit null and conflicts with `--color`. The list
stays on its board. Changing `--type` between `active` and `closed` is one
write: Planka itself closes or reopens the list's cards and completes or reopens
the tasks linked to them. Blockers on those cards therefore clear or return, and
`workflow next` eligibility changes, without client-side card or task writes.

`delete list` issues one native deletion of an explicit target without prompts.
Planka moves the list's cards to the board's trash list, with no position; they
are not deleted, and `get cards` no longer reads them. Deleting a board instead
removes its lists and cards. Archive and trash lists cannot be updated or
deleted: with `--board` that is `invalid_input` before any write.

Mutation `data` is the resulting list; delete adds `deleted: true`.
`meta.changed` is true, false for a no-op, or null when unknown. A rejected write
keeps the unchanged list (`changed: false`) with the native failure code. An
unknown or malformed write response returns `error.code: unknown_outcome`,
`changed: null`, and marks changed fields null (`deleted: null` for delete).
Unknown creates never invent a list ID and report `readback-lists` recovery for
the board: inspect `get lists --board BOARD` before retrying. Other mutations
report `readback-list`: inspect `get list LIST`. No request is retried
automatically.

Human reads print `NAME (LIST_ID) TYPE on board BOARD_ID` per list, with
`(unnamed)` for unnamed lists, or `No lists.`; limited output adds a truncation
notice. Mutations print `Created list`, `Updated list`, or
`Deleted list ... from board BOARD_ID`. Success exits 0, local input 2, other
failures 1. Writes require native board editor permission. See the [source
evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-eleventh-slice-lists).

### Canonical task lists

```sh
planka get task-lists --card CARD [--board BOARD] [--name NAME] [--limit N] -o json
planka get task-list TASK_LIST [--card CARD] [--board BOARD] -o json
planka create task-list --card CARD [--board BOARD] --name NAME [--position N] -o json
planka update task-list TASK_LIST [--card CARD] [--board BOARD] --name NAME -o json
planka delete task-list TASK_LIST [--card CARD] [--board BOARD] -o json
```

`task-list` and `task-lists` are aliases. TASK_LIST is an ID, or an exact name
with `--card CARD`; Planka has no task-list page URLs, so URL references are
`invalid_input`. A task-list ID alone finds its own card; an explicit `--card`
must contain it and an explicit `--board` must hold its card, otherwise the
mismatch is `invalid_input`. CARD follows the card rules: an ID, same-instance
URL, or exact name with `--board BOARD` or `PLANKA_BOARD_ID`. A name without
`--card` is `invalid_input` before any request; ambiguous names report candidate
IDs, and an absent or inaccessible ID is `not_found`.

Task-list `data` contains `id`, `cardId`, `name`, `position`,
`showOnFrontOfCard`, `hideCompletedTasks`, and nullable `createdAt`/`updatedAt`.
Tasks are not embedded; `describe card CARD` shows them. Individual reads return
an object with empty `meta`.

`get task-lists` requires `--card`. It returns every task list on the card from
the single native card read without paging, ordered by position then ID. Exact
`--name` matches before a positive `--limit`; `--label` and `--member` are
unsupported. `complete` describes matching task lists, and a malformed read
exits 1 with `complete: false`. Reads make no resource writes.

`create task-list` always creates a task list, even when the name exists, and
implies no workflow name such as `Acceptance criteria`. `--card` and `--name` are
required. It appends one position gap after the card's task lists unless
`--position N` gives a finite nonnegative native ordering value; Planka may
renumber positions. Only `name` and `position` are sent, so Planka's own defaults
apply: `showOnFrontOfCard` true and `hideCompletedTasks` false. Names are
nonempty and at most 128 characters.

`update task-list` requires `--name` and changes nothing else: tasks, their
completion, the task list's identity, position, and card are kept, and an
identical name is a no-op. Other fields are not accepted.

`delete task-list` issues one native deletion of an explicit target without
prompts. Planka deletes the task list's tasks with it and keeps the card and its
other task lists; the client deletes no task individually and never deletes the
card.

Mutation `data` is the resulting task list; delete adds `deleted: true`.
`meta.changed` is true, false for a no-op, or null when unknown. A rejected write
keeps the unchanged task list (`changed: false`) with the native failure code.
An unknown or malformed write response returns `error.code: unknown_outcome`,
`changed: null`, and marks changed fields null (`deleted: null` for delete).
Unknown creates never invent a task-list ID and report `readback-task-lists`
recovery for the card: inspect `get task-lists --card CARD` before retrying.
Other mutations report `readback-task-list` with the `task-list` resource:
inspect `get task-list TASK_LIST`. No request is retried automatically.

Human reads print `NAME (TASK_LIST_ID) on card CARD_ID` per task list, or
`No task lists.`; limited output adds a truncation notice. Mutations print
`Created task list`, `Updated task list`, or
`Deleted task list ... from card CARD_ID`. Success exits 0, local input 2, other
failures 1. Writes require native board editor permission. See the [source
evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-thirteenth-slice-task-lists).

### Canonical labels

```sh
planka get labels --board BOARD --name enhancement --limit 10 -o json
planka get label LABEL --board BOARD
planka create label --board BOARD --name enhancement --color berry-red
planka update label LABEL --board BOARD --name renamed --position 0
planka delete label LABEL --board BOARD
```

`label` and `labels` are aliases for each verb. BOARD is a numeric ID or
same-instance `/boards/ID` URL. Collection reads and creates require explicit `--board`. Individual
reads, updates, and deletes use `--board` or `PLANKA_BOARD_ID`; an explicit
board overrides the default. LABEL is an ID, same-instance `/labels/ID` resource
reference URL, or exact name in that board. These reference URLs are CLI forms,
not a claim that the web app has label pages. Board scope is required even for
label IDs: Community v2.2.1 has no individual label GET endpoint. A label absent
from the scoped snapshot fails with `not_found`; ambiguous names report candidate
IDs. No search or fallback to another board occurs.

Reads project only `id`, `boardId`, nullable `name`, `color`, `position`,
nullable `createdAt`, and nullable `updatedAt`. Individual `data` is an object;
collection `data` is an array, including `[]`. The board response supplies the
whole label collection without paging. Order by native position then ID
(numeric ID order). Exact `--name` filtering precedes positive
`--limit`; `meta.complete` describes the matching collection. Unsupported filters
and conflicting scalar values fail. Malformed records retain the validated,
matching results under the same order/limit with exit 1 and `complete: false`;
a failed board fetch returns `[]` with `complete: false`.

Create requires a nonempty name (at most 128 UTF-16 units) and a native color;
`create label --help` lists accepted colors. It always creates, even when the name
exists. Native positions are finite, nonnegative numbers rather than row indexes;
creation appends at the highest observed position plus 65536 when omitted.
Planka may normalize the requested position and reposition neighboring labels;
the CLI reports the returned position and issues no neighboring writes.
Update accepts supplied name/color/position only, rejects an empty update, and
skips an already-satisfied update. Names cannot be cleared through these commands;
existing unnamed native labels remain readable. Delete issues one target DELETE;
Planka removes its label assignments while retaining cards, boards, and other
labels. Missing label deletion fails rather than deleting a collection.
Card-label add/remove retain their idempotent relationship contract below.

Successful create/update `data` uses the read schema; delete adds `deleted: true`.
Mutation `meta.changed` is true for a confirmed write, false for a no-op or known
rejection, and null for an unknown outcome. Rejected create retains only the known board with other fields null;
rejected update/delete retains the prior label without a deletion marker.
Unknown create has null field values except the known `boardId` and any valid
new label ID returned by the response. Unknown update retains identity and omitted
fields, sets changed fields to null and keeps last-observed timestamps; unknown delete retains the
last observed label with `deleted: null`. Failed preparation reads have null
mutation `data` and `changed: false`.

Unknown writes are never blindly retried. `error.recovery.action` is
`readback-labels` when no label ID is known, with the board;
`readback-label` when an ID is known, with the board and label IDs. Read
`get labels --board BOARD` or `get label LABEL --board BOARD` to reconcile before
retrying. Create recovery may need inspection of all matching names because
names are not unique. Human output lists tab-separated ID, name, color, and
position; empty reads print `No labels.` and delete adds `deleted: true`.
Success exits 0, local input 2, operational/partial/unknown outcomes 1. Cleanup
failure preserves the primary result and emits a diagnostic.

[API evidence and verification limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-label-resource-operations)
are pinned to Community v2.2.1. Fixture and installed-gem checks do not prove live
acceptance or support across all 2.0.0+ versions and editions. Legacy `labels`,
`create-label`, and `apply-label`, including direct executables, retain their bare
JSON, effects, exits, and exact-name create reuse indefinitely.

### Canonical card members

```sh
planka get members --card CARD [--name NAME] [--limit N] -o json
planka get member USER --card CARD -o json
planka add member USER --card CARD -o json
planka remove member USER --card CARD -o json
```

`member` and `members` are aliases. USER is an account ID, same-instance
`/users/ID` URL, or exact display name among the card's board members. CARD is
an ID, same-instance URL, or exact name with `--board BOARD` or
`PLANKA_BOARD_ID`. BOARD accepts an ID or same-instance URL. Explicit card
IDs/URLs ignore the default board; an explicit `--board` must match the actual
parent. Ambiguous names report candidate IDs. Card-name lookup uses the native
board snapshot's finite lists; use an ID/URL for cards outside that snapshot.
Board-scoped member commands remain planned.

Read JSON contains `id` (user ID), `name`, nullable `username`, `cardId`,
`membershipId`, and nullable assignment `createdAt`/`updatedAt`; account email,
credentials, and unrelated account fields are excluded. Individual `data` is
an object with empty `meta`; collections are arrays ordered by numeric native
membership ID with `meta.complete`. Exact `--name` filtering precedes a positive
`--limit`; these flags are rejected on individual reads and writes. Completeness
describes matching results. Failed collections retain known hydrated results,
report `complete: false`, and exit 1. Reads use the card's complete native
membership collection and board identities, with no resource writes.

Mutations use the same object plus `assigned`. Existing-add and absent-remove
are no-ops (`meta.changed: false`); an absent-remove has null assignment metadata.
A confirmed write returns `changed: true`. An unknown write returns
`assigned: null`, `changed: null`, and `error.code: unknown_outcome`, preserving
known identities and prior membership metadata. Follow `error.recovery`'s
`readback-membership` action: inspect `get members --card CARD` before retrying.
There are no blind retries after an uncertain write. An unassigned individual
read is `not_found`; ambiguous names and explicit parent mismatches are
`invalid_input`. Native permission/authentication errors remain operational
failures. Other codes follow the shared canonical contract.

Human reads print `NAME (USER_ID) on card CARD_ID` per member, or
`No card members.`; limited output adds a truncation notice. Human mutations
also print `assigned: true|false`. Success exits 0, local input 2, other failures
1. Cleanup does not change the primary outcome. Add/remove require native board
editor permissions and preserve the user, card, list placement, and unrelated
assignments. Native subscription/activity effects apply; no workflow claim or
client cleanup writes are performed. See the [source evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-ninth-slice-card-members).

### Canonical card labels

```sh
planka add label LABEL --card CARD -o json
planka remove label LABEL --card CARD -o json
```

`label` and `labels` are aliases. LABEL is an ID, same-instance `/labels/ID`
CLI reference URL, or exact label name on the card's board. CARD is an ID, same-instance URL, or exact name with `--board BOARD`
or `PLANKA_BOARD_ID`, with the same scope rules as card members. Unknown labels
are `not_found`; ambiguous names report candidate IDs as `invalid_input`.

JSON `data` contains `cardId`, `labelId`, and `present`. Existing-add and
absent-remove are no-ops (`meta.changed: false`); a confirmed write returns
`changed: true`. An unknown write returns `present: null`, `changed: null`, and
`error.code: unknown_outcome`; follow `error.recovery`'s `readback-card-labels`
action and inspect `describe card CARD` before retrying. There are no blind
retries after an uncertain write.

Human output prints `Label LABEL_ID on card CARD_ID` and `present: true|false`.
Success exits 0, local input 2, other failures 1. Add/remove preserve the label,
the card, and unrelated labels, and apply no workflow convention. Endpoint
contract: Community v2.2.1 routes use POST card-labels and DELETE
card-labels/labelId:ID. See the [pinned source evidence and verification
limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#label-api-evidence).

### Canonical card tasks

```sh
planka update task TASK --card CARD --completed -o json
planka update task TASK --card CARD --no-completed -o json
```

`task` and `tasks` are aliases. TASK is a task ID or exact task name on the
card. CARD is an ID, same-instance URL, or exact name with `--board BOARD` or
`PLANKA_BOARD_ID`, with the same scope rules as card members. Unknown tasks are
`not_found`; ambiguous names report candidate IDs as `invalid_input`. Every
linked-card task, including linked Blocked by tasks, is refused as
`linked_task`.

JSON `data` contains `id`, `name`, `taskListId`, `cardId`, and `isCompleted`. An
already satisfied task is a no-op (`meta.changed: false`); a confirmed write
returns `changed: true`. An unknown write returns `isCompleted: null`,
`changed: null`, and `error.code: unknown_outcome`; follow `error.recovery`'s
`readback-task` action before retrying.

Human output prints `NAME (TASK_ID) on card CARD_ID` and
`completed: true|false`. Success exits 0, local input 2, other failures 1. Only
completion changes; no workflow convention is applied. This completion-only
consumer slice does not ship the other planned task verbs.

### Canonical card detail

```sh
planka describe card CARD
planka -o json describe card CARD
planka describe cards CARD --output json
planka describe --help
planka describe card --help
```

This read-only command accepts numeric card IDs and card URLs belonging to
`PLANKA_BASE_URL`. It requires nonempty `PLANKA_BASE_URL`, `PLANKA_AGENT_EMAIL`,
and `PLANKA_AGENT_PASSWORD` before network access; no board setting is required.
Common output flags work before or after the command path. Human output matches
legacy `show`; JSON wraps the detail in `data`, alongside `meta: {}` and `error: null`.
On failure, `data` is null and `error` contains a code and message. Invalid input
exits 2; configuration, API, and network failures exit 1. Session cleanup
failures are reported on stderr without replacing the read result. See the
[leaf contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#first-leaf-output-contract)
for fields and error codes. No live-version capability check is implemented.

### Canonical board description

```sh
planka describe board BOARD
planka -o json describe boards BOARD
planka describe board --help
```

Supply a numeric board ID or a board URL belonging to `PLANKA_BASE_URL`.
The target is required even when `PLANKA_BOARD_ID` is set. The same connection
and credential validation applies as for card detail. Board names and project
lookup are not yet supported.

Human output matches `snapshot --board BOARD`. JSON puts the board snapshot in
`data`, with `boardId`, `lists`, `cards`, `labels`, `cardLabels`, `taskLists`,
`tasks`, and `cardMemberships`, alongside `meta: {}` and `error: null`. Cards have
URLs and sort by position. This read describes the endpoint's included snapshot;
it does not implement collection pagination, filters, `--limit`, or completeness
metadata. See the [board contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-second-slice-board-description).
Legacy `snapshot --list` remains available with its existing output.

### Canonical pending criteria

```sh
planka workflow pending-criteria CARD
planka -o json workflow pending-criteria CARD
planka workflow --help
```

This read-only workflow accepts an explicit card ID or same-instance card URL.
It requires the three connection/credential variables above, without a board
setting. It reads the card's board and returns unfinished tasks from lists named
exactly `Acceptance criteria`, preserving board-response order. Human output is
one criterion per line; JSON has `data: {cardId, criteria}`, `meta: {}`, and
`error: null`. No criteria, including a card without that task list, is a
successful empty array. Human output is then a blank line, matching `unticked`.
See the [pending-criteria contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-third-slice-pending-criteria).

### Canonical branch name

```sh
planka workflow branch-name CARD
planka -o json workflow branch-name CARD
planka workflow branch-name --help
```

This read-only workflow accepts an explicit card ID or same-instance card URL
and requires the three connection/credential variables. It uses the first
`feature:` label in the existing board association order, the card's title slug,
and legacy truncation rules. Human output is the branch name; JSON has
`data: {cardId, branch}`, `meta: {}`, and `error: null`.

Optional `PLANKA_BRANCH_PREFIX` reserves space in the 63-character length budget;
it is not prepended to the returned branch. A prefix longer than 55 characters
fails before network access as a configuration error. A board setting is not
required. This command computes a name without creating a Git branch or changing
Planka. See the [branch-name contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-fourth-slice-branch-name).

Workflow conventions now live in an explicitly loaded `Planka::Workflow` module,
with separate core resource models and workflow CLI integration. See the
[module architecture and future gem extraction](docs/WORKFLOW_MODULE.md).

### Canonical claim status

```sh
planka workflow claim-status
planka workflow claim-status -o json
planka workflow claim-status --help
```

This read-only inspection uses the signed-in user's claims across all accessible
boards. It reports the first open claimed card without a PR handoff, following
legacy `loop-lock` rules, except that a card labelled `quarantine` never holds
the claim (legacy `loop-lock` still reports it). It does not acquire a lock,
change resources, or query GitHub. An empty board scope or no eligible card is a successful `free` result.

The three connection/credential variables are required. There is no positional
target or `--board` flag; `PLANKA_BOARD_ID` does not restrict this operation.
Human output matches `loop-lock`. JSON has `data: {held, card}`, with `claimedAt`
and integer `ageSeconds` when held, plus `meta: {}` and `error: null`. Malformed
required records produce a sanitized error rather than a guessed `free` result.
See the [claim-status contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-fifth-slice-claim-status).

### Canonical workflow guide

```sh
planka workflow guide
planka workflow guide -o json
planka workflow guide --help
```

Prints concise built-in agent guidance without credentials, network access, or
an API session. Connection and workflow settings are ignored. There is no target
or scope flag. Human output is the guide text; JSON is
`{"data":{"instructions":"..."},"meta":{},"error":null}`. Invalid input exits 2
with canonical errors. Guidance uses implemented canonical commands and marks
remaining legacy operations explicitly. Legacy `prime` keeps its original text
and bare JSON. See the [guide contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-sixth-slice-workflow-guide).

### Canonical next work

```sh
planka workflow next --board BOARD
planka workflow next --label feature:search -o json
planka workflow next --board BOARD --label effort:search --label enhancement
```

Selects work without claiming it or changing resources. `--board` accepts a
numeric board ID or same-instance board URL; otherwise `PLANKA_BOARD_ID` supplies
scope. The three connection/credential variables remain required. No mode label
uses ready-for-agent priority by position; `feature:` uses ticket creation order;
`effort:` returns the wayfinder map and takeable frontier by position. Repeated
`--label` values AND-match before selection. At most one distinct `feature:` or
`effort:` label selects a mode; other labels narrow that queue, including specs
and maps. Cards labelled `quarantine` are never selected, by this command or
legacy `next-card`. Unknown labels and empty queues succeed with no card.

Human output matches `next-card`. Canonical JSON wraps its pick, waiting, or
frontier data in `data`, with empty `meta` and null `error`. Completed linked tasks
retain blocker handoff/parent metadata; unfinished linked tasks prevent selection.
Only selected priority/feature blockers need comment and PR reads. `gh` must be
installed for recorded PR lookups and authenticated for private repositories.
Failed lookups retain an unknown PR state and recorded branch; malformed records
fail safely. No handoff or multiple unmerged blockers report `AMBIGUOUS`.
There is no `--limit`, collection pagination, or `meta.complete` claim. See the
[next-work contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work).

### Canonical claim

```sh
planka workflow claim CARD
planka workflow claim CARD -o json
planka workflow claim --help
```

Claims an explicit card for the signed-in user, adding membership before moving
it to its board's unique `in-progress` list. Requires the three connection
environment variables, without a board setting. Existing membership is retained;
cards already in progress keep their position. An already-satisfied claim succeeds
without resource writes. A move requests native position 65535 and reports the
server's resulting position. Other users' memberships are retained; this is not
an exclusive lock or atomic transaction.

Human output reports `claimed`, `member added`, and `moved`. JSON `data` contains
`card: {id, name, listId, position, url}`, `userId`, `inProgressListId`, nullable
`membershipId`, and `claimed`, `memberAdded`, `moved` booleans. `meta.changed` is
true for confirmed effects and false for a no-op. Membership IDs are retained
when available, including when a later move fails.

Failures preserve known results, with null for uncertain step outcomes.
`error.code` is `partial_failure` when a later step is rejected after a confirmed
change, or `unknown_outcome` when a write cannot be confirmed. `meta.changed`
remains true if an earlier effect is confirmed; otherwise it is null for an
uncertain write and false for a known unchanged failure. Recovery is
`{action: "readback-claim", resources: [{type: "card", id: CARD}]}`. Run
`planka describe card CARD -o json` to inspect membership and list placement
before deciding to retry. No automatic uncertain-write retry or rollback occurs.
Other failures retain the canonical input/configuration/authentication/
authorization/not-found/API/network codes. Success exits 0, local input 2, other
failures 1. Cleanup failure warns on stderr and preserves the primary outcome.
See the [claim contract and API evidence](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-eighth-slice-claim-a-card).

### Canonical create spec

```sh
planka workflow create spec --list ready-for-agent --board BOARD --name "Search" --description-file spec.md
planka workflow create spec --list LIST_ID --name "Search" --description-file - -o json < spec.md
planka workflow create spec --list LIST_ID --name "Search" --position 0
planka workflow create --help
```

Creates one `project` card without an `Acceptance criteria` task list, even when
the board's default card type is `story`. Repeated names create distinct cards;
this is not an upsert. The command adds no tasks, memberships, labels, or comments.
`spec`/`specs` are aliases. It accepts no positional target or criteria flag.

`--list` and `--name` are required. LIST is a numeric ID, same-instance list URL,
or an exact name on `--board BOARD` or `PLANKA_BOARD_ID`. BOARD is an ID or
same-instance board URL; an explicit board asserts the actual parent. List IDs
and URLs determine their board and ignore the environment default. Absent list
names discovered through API lookup and ambiguity exit 1; ambiguity keeps the `invalid_input`
code and reports candidate IDs. Explicit parent mismatches exit 2.

Names are nonempty, at most 1024 UTF-16 code units. Optional
`--description-file FILE|-` reads nonempty UTF-8 text of at most 1048576 UTF-16
units before authentication, preserving Unicode, quotes, and final newlines.
An omitted description is null. Empty/unreadable/invalid text is local input
failure. The three connection settings are required and checked before file
reading; no configuration or token is persisted.

Active/closed lists append after the highest observed position plus 65536,
unless `--position N` supplies a finite nonnegative native value. Native
normalization may move neighbors; the returned position is authoritative.
Append is not atomic with concurrent changes. Archive/trash lists require
explicit board scope, omit position, and reject `--position`.

Human success is `Created spec NAME (CARD_ID) in list LIST_ID`. JSON uses the
canonical envelope; `data` is a card object with `id`, `name`, `description`,
`type`, `boardId`, `listId`, `position`, `createdAt`, and `updatedAt`.
Description, position for archive/trash, and optional timestamps may be null.
Confirmed success has `meta: {changed: true}` and `error: null`.

Before scope is observed, failures have `data: null`. Rejected writes retain the
observed placeholder: board/list IDs and null card fields, with `changed: false`.
Unknown or malformed write responses use `unknown_outcome` and `changed: null`;
unconfirmed fields remain null. A valid numeric returned ID absent from the
observed cards is retained for reconciliation, without claiming a confirmed
create. IDs are never invented, and an already observed ID cannot confirm a create.

For a known ID, recovery is
`{action: "readback-card", resources: [{type: "card", id: CARD}]}`:
inspect `planka get card CARD -o json`. Otherwise recovery is
`{action: "readback-cards", resources: [{type: "list", id: LIST}]}`:
inspect `planka get cards --list LIST -o json` for active/closed lists, or inspect
archive/trash in Planka. Compare name and description before deciding whether
to create again. Neither automatic retry nor rollback occurs.

Stable errors are `invalid_input`, `configuration_error`, `authentication_error`,
`authorization_error`, `not_found`, `api_error`, `network_error`, and
`unknown_outcome`. Resolved mutation failures include `meta.changed`; grammar
failures use the shared parser envelope. Success exits 0, local input 2, and
configuration/API/lookup/unknown outcomes 1. Sign-out is attempted after execution;
cleanup failure warns on stderr and preserves the primary result. Native board
editor permission is required. This is one card write, without a multi-step
criteria workflow. See the [API evidence and verification limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-create-spec-workflow).

Legacy `create-spec --title TITLE` and `planka-create-spec` retain their argument,
bare `{card: {id, name, url}}` JSON, human output, and exit contracts. Their help
names the implemented canonical command; runtime warnings are not added.

### Canonical resume ticket

```sh
planka workflow resume ticket CARD --criteria-file criteria.json
planka workflow resume ticket CARD --criteria-file - -o json < criteria.json
planka workflow resume --help
planka workflow resume ticket --help
```

Finishes an existing ticket by adding the acceptance criteria missing from its
`Acceptance criteria` task list. It never creates a card. `CARD` is a numeric ID
or same-instance card URL; `ticket`/`tickets` are aliases. The three connection
environment variables are required, without a board setting.

`--criteria-file FILE` (`-` for stdin) is required: a nonempty JSON array of
distinct criteria, each a nonblank string of at most 1024 characters (Planka's
task-name limit). The file is read and validated before any request; an
unreadable file, malformed JSON, or a bad shape exits 2 with `invalid_input`.
Missing connection settings are checked first and exit 1.

The card's single criteria list is reused and created only when absent, so a
card without one becomes a ticket. A criterion already present by exact text is
kept with its completion, text, and position. Missing criteria are appended
after the list's existing tasks in file order. Other tasks are never changed or
deleted. When every criterion is present the command makes no writes and
reports `meta.changed: false`. Two or more criteria lists fail before any write
with `ambiguous_criteria_list`, naming the candidate list IDs.

Human output reports `resumed`, `criteria list created`, `criteria added`, and
`criteria kept`. JSON `data` contains `card: {id, name, url}`,
`taskList: {id, name, created}`, and `tasks: [{id, name, isCompleted, created}]`
in criteria order. `meta.changed` is true when anything was created.

Failures preserve known results. An uncertain write is reported with a null
`id`, `created`, and (for tasks) `isCompleted`; no ID is invented. `error.code`
is `partial_failure` when a write is rejected after an earlier confirmed change,
or `unknown_outcome` when a write cannot be confirmed. `meta.changed` stays true
after a confirmed effect; otherwise it is null for an uncertain write and false
for a known unchanged failure. Recovery is
`{action: "resume-ticket", resources: [{type: "card", id: CARD}, {type: "task-list", id: LIST}]}`,
with the task list only when its ID is known. Inspect with
`planka describe card CARD -o json`, then rerun the same command: it reads the
card first and adds only what is still missing. Writes are never retried or
rolled back. Other failures keep the canonical input/configuration/
authentication/authorization/not-found/API/network codes. Success exits 0,
local input 2, other failures 1. Cleanup failure warns on stderr and preserves
the primary outcome. See the
[resume contract and API evidence](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-twelfth-slice-resume-a-ticket).

### Canonical comments

```sh
planka get comments --card CARD [--limit N]
planka get comment COMMENT --card CARD
planka create comment --card CARD --text "Ready for review"
planka update comment COMMENT --card CARD --text "Updated note"
planka delete comment COMMENT --card CARD
```

All commands accept `comment`/`comments`, `--board BOARD`, `-o human|json`, and
work offline with `--help`. `COMMENT` is a numeric ID: comments have no names or
supported URLs. Every command requires `--card` because the verified API has no
individual comment GET. Cards accept IDs, same-instance `/cards/ID` URLs, or exact
names within `--board`/`PLANKA_BOARD_ID`. Explicit card IDs and URLs ignore the
default board; explicit `--board` must agree. Ambiguous card names list candidate
IDs. A comment absent from the asserted card is `not_found`; it is never mutated.

Collection reads fetch all native 50-item pages, ordered by descending numeric
comment ID (newest first). There are no name/label/member filters. A positive
`--limit` caps results after paging; `meta.complete` is false when truncated or
retrieval fails. A failure returns verified partial comments with exit 1, even
when a requested limit was already filled. An exact page boundary requires the
next page to establish completeness. Concurrent changes can affect the result;
these reads do not promise a consistent snapshot. Individual reads search those
pages until the target is found.

Creation always posts a new comment once, even for repeated text. Creation and
update require `--text`: nonblank UTF-8, at most 1,048,576 UTF-16 code units (an
emoji can occupy two). Text is sent exactly, including newlines and surrounding
whitespace. Empty/blank input fails; clearing text is unsupported. The shell/OS
may impose a lower argument-size limit. Update sends only text and an identical
value is a no-op. Native creation requires board editor or viewer `canComment`
permission; updates additionally require authorship. Deletion permits a project
manager, or the author with those board permissions. The server remains the
permission authority. Reads require access to the card. An identical-text no-op
needs read access and makes no permission-probing write.

Native deletion removes only the comment, preserving the card and other comments.
Planka maintains its comment count, timestamps, notifications, and events; the
CLI issues no extra cleanup mutations. No prompt or cascade flag is used.

Human reads show `Comment ID on card CARD` followed by the exact text, or
`No comments.`. Mutations prefix that rendering with `Created`, `Updated`, or
`Deleted`. Limited collections include a truncation notice.

JSON uses `{data, meta, error}`. A comment object contains `id`, `cardId`, nullable
`userId`, `text`, and nullable `createdAt`/`updatedAt`; unrelated native fields are
excluded. Collections return an array and `meta.complete`; individual reads
return an object and empty `meta`. Successful mutations return the comment and
`meta.changed: true`; identical updates return false. Delete adds `deleted: true`.
Rejected writes return the last observed state with `changed: false` (a rejected
create has only its card known); failures before observation return null data.
Unknown or malformed write responses use `changed: null`, preserve known identity
and unchanged fields, and set requested uncertain fields to null. Unknown deletion
adds `deleted: null`. A usable created ID in a malformed response is retained.

Recovery contains `action: readback-comment` and card/comment resource IDs when
the comment ID is known, otherwise `readback-comments` and the card ID. Read with
`get comment COMMENT --card CARD` or `get comments --card CARD` and reconcile
before retrying; no write is automatically resent. Missing settings fail before
requests. Sessions remain in memory; cleanup failures preserve the primary result.
Exits are 0 success, 2 local input, 1 operational/API/unknown outcome.

Legacy `comment CARD TEXT` and `planka-comment` retain positional text, bare JSON,
stdout/stderr, and exits. Their help names `create comment`. Existing `show`,
`describe`, handoff parsing, and claim inspection keep their one-page comment
reader. See [pinned API evidence and verification limits](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-comment-resource-operations).

### Legacy compatibility commands

The installed CLI also retains the flat commands below. Run
`planka <command> --help` for full arguments and options. Each operation also
has a direct `planka-<command>` executable.

These flat commands and direct executables are deprecated in the redesign
contract and retained indefinitely with their existing arguments, behavior, JSON
shapes, and exit codes. No removal is scheduled; a later sweep belongs to a
separate track of work. Deprecation notices appear in documentation, help, and
release notes, with no automatic runtime warnings. `describe card` replaces
`show`, `describe board` replaces the board view of `snapshot`, and
`workflow pending-criteria` replaces `unticked`, and `workflow branch-name`
replaces `branch-name`, `workflow claim-status` replaces `loop-lock`, and
`workflow guide` replaces `prime`, `workflow next` replaces `next-card`, and
`workflow claim` replaces `claim`, `workflow create spec` replaces `create-spec`, and `workflow resume ticket` replaces
`create-ticket --card`, `update card` replaces `update-card`,
`move card` replaces `move-card`, `get cards --list LIST` replaces the list
view of `snapshot`, `create list` replaces `create-list`, and
`create task-list` and `update task-list` replace `create-task-list` and
`rename-task-list`, and `create comment` replaces `comment`; remaining canonical replacements are not yet implemented.

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
planka workflow resume ticket CARD --criteria-file criteria.json -o json
```

This adds only missing criteria and never creates another card; the legacy
`planka create-ticket --card CARD --criteria-file criteria.json` remains available. `claim`, `link`, and `apply-label` may be safely
repeated, and `create-label` reuses an existing label with the same name.

## Library

```ruby
require "planka"

Planka::Client.session do |client|
  board = Planka::Board.new(client.board(ENV.fetch("PLANKA_BOARD_ID")),
    base_url: ENV.fetch("PLANKA_BASE_URL"))
  puts board.cards.first
end
```

`Board` also accepts a captured API `included` payload. Supply `base_url:` when
using multiple instances in one process. Load `planka/workflow` explicitly for
agent conventions, then wrap a core board with `Planka::Workflow::Board.new(board)`.
`Planka::Workflow::BranchName.for(workflow_card, prefix: "app-")` accepts a
per-call prefix. Historical workflow Ruby paths and constant aliases are removed;
legacy CLI commands remain available.

Card-scoped resources accept an authenticated client and explicit scope. Reuse
the object within the session; each operation reads current server state:

```ruby
Planka::Client.session(validate_responses: true) do |client|
  projects = Planka::Projects.new(client, base_url: ENV.fetch("PLANKA_BASE_URL"))
  projects.all(name: "Product", limit: 10)                     # CollectionResult
  projects.find("123")                                        # ID or exact instance-scoped name
  projects.create(name: "Product", type: "private", description: "Roadmap")
  projects.update("123", description: nil)                     # Explicit clearing
  projects.delete("123")                                      # Native empty-project restriction

  members = Planka::Cards::Members.new(client, card_id: "123")
  members.all                     # CollectionResult: data and complete
  members.find("456")              # One assigned user's public fields
  members.include?("456")          # Boolean: is this user assigned?
  members.add("456")               # MutationResult: data and changed
  members.remove("456")            # MutationResult: data and changed

  labels = Planka::Cards::Labels.new(client, card_id: "123")
  labels.include?("enhancement")   # Boolean: is this board label attached?
  labels.add("enhancement")
  labels.remove("enhancement")

  tasks = Planka::Cards::Tasks.new(client, card_id: "123")
  tasks.update("789", completed: true)

  boards = Planka::Projects::Boards.new(client, base_url: "https://planka.example", project_id: "600")
  boards.all(name: "Delivery", limit: 10)  # CollectionResult; complete visible project collection
  boards.find("100")                      # project_id optional for an ID
  boards.create(name: "Delivery")          # MutationResult; append by default
  boards.update("100", name: "Development")
  boards.delete("100")                    # Native deletion, including the board's contents

  cards = Planka::Boards::Cards.new(client, board_id: "100")  # board_id optional for IDs
  cards.all(list: "Ready", labels: ["enhancement"])           # CollectionResult
  cards.find("123")                                            # One card's public fields
  cards.create("Ready", name: "Fix login", description: "...") # MutationResult
  cards.create("Ready", name: "Search", type: "project")       # Explicit native type; default otherwise
  cards.update("123", name: "Fix session expiry")
  cards.move("123", list: "Done")
  cards.delete("123")

  lists = Planka::Boards::Lists.new(client, board_id: "100")   # board_id optional for IDs
  lists.all(name: "Ready", limit: 5)                           # CollectionResult; needs board_id
  lists.find("Ready")                                          # One list's public fields
  lists.create(name: "Review", type: "active")                 # MutationResult; needs board_id
  lists.update("200", name: "Done", type: "closed", color: nil) # color: nil clears it
  lists.delete("200")

  board_labels = Planka::Boards::Labels.new(client, board_id: "100") # board required for all operations
  board_labels.all(name: "enhancement", limit: 5)                    # CollectionResult
  board_labels.find("enhancement")                                  # One label's public fields
  board_labels.create(name: "enhancement", color: "berry-red")       # Always creates
  board_labels.update("300", name: "renamed", position: 0)
  board_labels.delete("300")
end
```

Member, label, and task references accept IDs or exact scoped names. Constructors also
accept `board_id:` to assert the card's board or resolve a card name within it;
they do not read environment defaults or open a session. `Members#all` accepts
an exact string `name:` filter and positive integer `limit:`; invalid option
values raise `ArgumentError` before resource reads. `Tasks#update` changes
only completion, requires a Boolean, and refuses linked tasks. Repeated
already-satisfied mutations return `changed: false`.

Members and labels share the `Relationship` role: `add`, `remove`, and `include?`.
Only a known target with no association returns `false` from `include?`. Unknown
or ambiguous targets raise `ReferenceError`; failed or malformed reads raise
their original errors. Removing an association preserves its target and card.

`Planka::Resource` implements protected `create`, `update`, and `delete`
algorithms: prepare input, resolve current state, skip satisfied changes, execute
the request, validate its response, and construct the result. `Tasks` exposes
the inherited `update` publicly. `Relationship#add` and `#remove` use inherited
create/delete operations on associations. Each resource supplies its lookup,
request, validation, projection, and readback details, and exposes only supported
public operations.

Mutation failures raise `Planka::MutationFailure` with `data`, `changed`,
`uncertain`, and `recovery`; use readback before retrying an uncertain write.
Collection failures raise `Planka::CollectionFailure` with known partial `data`.
The CLI uses these same resource methods. The former member/task `.read`
dispatchers are replaced by these instance methods.

## Development and extraction boundary

Before implementation, refactoring, or review, read the
[coding standards](CODING_STANDARDS.md). Agent skill entry points and tracker
conventions are in [AGENTS.md](AGENTS.md). Settled project terminology is in the
[domain glossary](CONTEXT.md).

`make test` runs the captured-board tests and local HTTP command tests.
`make build` builds the gem; `bundle exec make lint` runs RuboCop;
`bundle exec make ci` runs lint, tests, and the build. CI covers Ruby 3.2, 3.4 and 4.0.

RuboCop targets Ruby 3.2 and checks `lib`, `test`, the extensionless `exe/*`
commands, `Gemfile`, and the gemspec. `.rubocop.yml` enables lint/security, layout,
and selected style and Minitest checks. It uses double-quoted strings and trailing
commas in multiline array/hash literals. Metrics, line-length limits, and mandatory
class documentation are disabled; responsibility, dependency, and abstraction
judgments remain part of review against `CODING_STANDARDS.md`. Exact boolean
assertions and multiple assertions per integration test remain allowed.

Use `bundle exec rubocop -a` for safe autocorrections, then review the diff and
run `bundle exec make ci`. `-A` also applies unsafe corrections and should not
be used as routine formatting. New cops are disabled until reviewed; update the
RuboCop and Minitest-extension version bounds in `Gemfile` deliberately. The
repository continues to ignore `Gemfile.lock`; local dependency resolutions stay
in the development checkout. Keep any suppression limited to the relevant code
and explain the contract or trusted input that justifies it.

The tests do not contact a live Planka instance. API endpoints and payload shapes
are inherited from Lucenta, including its captured Community board fixture;
compatibility with other Planka releases has not been established.

Lucenta continues using its original library and 1Password integrations.
Switching it to this gem is a separate consumer change once a repository or
release is available to CI. No release license has been selected; choose one
before publishing the gem.
