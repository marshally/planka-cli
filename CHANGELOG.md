# Changelog

## Unreleased

Added native comment resource reads, creation, text-only updates, and deletion
with singular/plural aliases and offline help. All require explicit card scope;
comment IDs have no URL/name lookup. Collections follow native 50-item descending
ID pages, report limit completeness, and retain valid partial results on failure.
Multiline Unicode text is preserved exactly; blank input and clearing are rejected.
Updates skip identical text, writes are sent once, and uncertain outcomes retain
known IDs with readback recovery. Legacy comment commands keep their runtime
contracts; their help and the current agent guide name `create comment`.
Official Community v2.0.0, 2.1.1, and v2.2.1 sources were inspected; no live writes
or live API acceptance were performed.

Added board label resource commands: `get labels --board BOARD` (exact name,
limit, and completeness), `get label LABEL`, `create label --board BOARD --name
NAME --color COLOR [--position N]`, `update label LABEL`, and `delete label LABEL`,
with aliases and offline help. IDs and CLI reference URLs also require board
scope for individual operations. Canonical creation always creates, updates
send only supplied changed fields, and native deletion removes assignments while
preserving cards. Malformed reads retain valid partial results; unknown writes
preserve known IDs and require readback without retries. `Boards::Labels` uses
the shared Resource/Write lifecycle. Legacy label commands retain exact-name
reuse, arguments, JSON, exits, and runtime output; their help names replacements.
API evidence is pinned to Community v2.2.1 source, without live write acceptance.

Added card task-list resource commands with singular/plural aliases and offline
root/group/leaf help: `get task-lists --card CARD` (card order, exact `--name`,
`--limit`), `get task-list TASK_LIST`,
`create task-list --card CARD --name NAME [--position N]`,
`update task-list TASK_LIST --name NAME`, and `delete task-list TASK_LIST`.
TASK_LIST is an ID or an exact name with `--card`; an ID alone finds its card,
and URL references are rejected because Planka has no task-list pages. Creates
append after the card's task lists and send only the name and position, so
Planka's display defaults apply; updates rename only and keep tasks; deletes
issue one native deletion, and Planka deletes the list's tasks. Unknown outcomes
report `readback-task-lists` or `readback-task-list` recovery without retries
or invented IDs. They replace legacy `create-task-list` and `rename-task-list`,
which remain unchanged; their help names the replacements. Task-list operations
live under `Planka::Cards::TaskLists` with `TaskListScope` and `TaskListRecord`,
and `CLI::Resources::Cards::TaskLists`. A command without a URL collection now
accepts only ID and name references.

Added `workflow resume ticket CARD --criteria-file FILE|-` (alias `tickets`) with
offline help at `workflow resume` and the leaf. It adds the criteria missing from
an existing ticket's `Acceptance criteria` list and never creates a card. The
list is reused, or created when absent. Existing criteria keep their completion,
text and order, and missing ones are appended in file order. An all-present run
is a no-op, and two or more criteria lists fail as `ambiguous_criteria_list`
before writes. Criteria are read and validated before any request as a nonempty
JSON array of distinct nonblank strings of at most 1024 characters. Failures
keep known IDs, report uncertain steps as null, and recover with `resume-ticket`
by rerunning the command. It replaces legacy `create-ticket --card`, which
remains unchanged; its help and the workflow guide name the replacement.
Canonical catalogs now support three-word command paths with nested group help;
groups are keyed by path arrays. Canonical task-list and task creates report a
missing `item` as an invalid response.

Added native list resource commands with singular/plural aliases and offline
root/group/leaf help: `get lists --board BOARD` (every native list type in board
order, exact `--name`, `--limit`), `get list LIST`,
`create list --board BOARD --name NAME [--type active|closed] [--position N]`,
`update list LIST` (`--name`, `--color` or `--clear-color`, `--position`,
`--type active|closed`), and `delete list LIST`. Creates append after the
board's active and closed lists; updates send only supplied, changed fields,
with `--clear-color` sending null, and keep the list on its board; deletes issue
one native deletion, and Planka moves the list's cards to trash. A type change
is one write whose native effects close or reopen the list's cards and the tasks
linked to them. Archive and trash lists cannot be created, updated, or deleted.
Unknown outcomes report `readback-lists` or `readback-list` recovery without
retries or invented IDs. `create list` replaces legacy `create-list`, which
remains available unchanged; its help names the replacement. List operations
live under `Planka::Boards::Lists` with `ListScope` (extracted from `CardScope`)
and `ListRecord`, and `CLI::Resources::Lists`; cards and lists share
`CLI::Resources::BoardScope`, `CollectionResult.limited`, and
`Records.text?`/`Records.position?`.

Removed all HTTP retries. Every request, read or write, canonical or legacy, is
sent exactly once: the three-attempt client loop, its stderr retry warnings and
sleeps, net-http's internal retry, and the per-call `idempotent:` flags are gone.
A write that fails after reaching Planka reports an unknown outcome for
read-back, so legacy `update-card`, `move-card` and `rename-task-list` now print
their reconcile message instead of silently re-sending.

Added native card resource commands with singular/plural aliases and offline
root/group/leaf help: `get cards --board BOARD|--list LIST` (exact `--name`,
repeated AND `--label`/`--member`, `--limit`, reading active and closed lists
only), `get card CARD`, `create card --list LIST --name NAME`,
`update card CARD`, `move card CARD --list LIST`, and `delete card CARD`. Creates
use the board's default card type and append unless positioned; updates send
only supplied, changed name/description fields; moves stay on the card's board;
deletes issue one native deletion. Unknown outcomes report `readback-cards` or
`readback-card` recovery without retries or invented IDs. These replace legacy
`update-card`, `move-card`, and the list view of `snapshot`, which remain
available unchanged; their help names the replacements. Card operations live
under `Planka::Boards::Cards` and `Boards::CardMove`, with shared `CardScope` and
`CardRecord`, and `CLI::Resources::Cards`. `Resource#create`
now takes validated attributes and a creation scope, create/update requests
receive the desired state, and catalog preparation receives the resolved
positional reference. Canonical commands treat arguments and description files
as UTF-8 whatever the process locale and reject invalid UTF-8 as `invalid_input`;
previously a non-ASCII argument under a C locale could crash.

Added card-scoped `update task TASK --completed|--no-completed` with a plural
alias, offline help, and the same card scope, reference failures and write
outcome classification as card members and labels. TASK is a task ID or exact
name on the card. Linked tasks are refused as `linked_task`; a satisfied task is
a no-op, and unknown writes report `isCompleted: null` and require
`readback-task`. Task operations live under `Planka::Cards::Tasks` and
`CLI::Resources::Cards::Tasks`; `update` group help lists them.

`workflow claim-status` ignores claims on cards labelled `quarantine` and accepts
native archive and trash lists, including unnamed ones; claim scope accepts the
same lists. Legacy `loop-lock` keeps its original claim rule.

Added card-scoped `add label LABEL` and `remove label LABEL` with singular/plural
aliases, offline help, and the same card scope, reference failures and write
outcome classification as card members. LABEL is a board label ID or exact name
on the card's board. Add/remove are idempotent on satisfied relationships and
preserve unrelated labels; unknown writes report `present: null` and require
`readback-card-labels`. Card scoping is shared through `Planka::Cards::Scope`
and `CLI::Resources::Cards.prepare_scope`; reference resolution through
`Planka::Reference`. Group help for `get`, `add` and `remove` now lists each
relationship with a short description.

Workflow selection never picks a card labelled `quarantine`, in `workflow next`
and, as a deliberate exception to the legacy retention contract, legacy
`next-card`. Waiting reports mark such cards `quarantined` in human output and
with a `quarantined` boolean in JSON.

Applied a POODR design review to the library. Planka positions, network-error
classification and response-record checks each have one owner (`Planka::Position`,
`Planka::Client`, `Planka::Records`). Canonical commands are `CLI::Command`
values. Next-card reports answer `as_json`. Each `Planka::Card` carries its own
related records; `Board#label_names`, `#task_list_names`, `#tasks`, `#tasks_in`,
`#members`, `#memberships`, `#list_type` and `#base_url` are removed in favor of
the card's methods. `PullRequest` is a plain value; `PullRequest.find` moved to
`PullRequestLookup::Legacy`, and `Workflow::Format.next_card`, `card_ref` and
`blocker_ref` are removed. Command behavior, output and legacy contracts are
unchanged.

Added card-scoped `get members`, `get member USER`, `add member USER`, and
`remove member USER`, with singular/plural aliases, offline help, scoped exact
names, minimal identity/assignment results, name filtering, and complete/limited
collections. Add/remove are idempotent on satisfied relationships and preserve
list placement. Unknown writes retain identity and require readback; non-idempotent
requests disable net-http's internal retry as well as blind client retries.
Community 2.0.0, 2.1.1, and 2.2.1 source evidence is recorded; live acceptance
and other editions/releases remain unverified. Legacy CLI contracts are retained.

Card-member operations live under `Planka::Cards::Members`; their CLI definitions
live under `Planka::CLI::Resources::Cards::Members`. Resource-specific command
modules sit beneath their parent resource, separate from shared parsing and
presentation machinery. The earlier internal CardMembers constants and paths
are removed; command behavior is unchanged.

Card and board command definitions and formatters now live under
`CLI::Resources::Cards` and `CLI::Resources::Boards`; `Resources` combines their
definitions and help. Core CardDetail and Snapshot readers moved to
`Cards::Detail` and `Boards::Snapshot`, with matching file paths and no obsolete
Ruby aliases or formatter forwarding methods. Legacy show/snapshot adapters use
the same resource-owned formatters. Root Card/Board models, workflow ownership,
command/help text, outputs, and exits retain their existing contracts.

Added `planka workflow claim CARD` with canonical results, effect metadata,
offline help, membership-then-move behavior, and no-op reclaims. Partial failures
retain confirmed effects and membership IDs; unknown writes require readback
before retrying. Legacy flat/direct claim output and behavior remain intact.

Named direct Planka operations “resource commands” in help and documentation.
Workflow commands apply project conventions; these categories describe behavior
and do not imply administrator privileges. The internal catalog is now
`CLI::Resources` in `planka/cli/resources`; the previous internal name and path
are removed.

Separated canonical CLI catalogs, parsing, immutable invocations, captured
connection settings, instance reference resolution, and command preparation.
Reader inputs and scope validation finish before sessions open. Workflow
preparation owns default-scope error classification. Command behavior, output,
errors, legacy contracts, and library loading remain unchanged. Parsing now
expresses its validation stages through private methods, preserving help/error
ordering and removing redundant parser state.

Added read-only `planka workflow next` with explicit/default board scope,
AND-matching labels, canonical JSON/errors, and existing priority/feature/frontier
selection and stacking rules. Canonical reads validate eligibility records and
sanitize GitHub lookup results. Empty queues succeed; legacy next-card contracts
remain intact. Help and the built-in canonical guide name the replacement.

Added `planka workflow guide` with human text and canonical JSON, without
credentials or an API session. It uses implemented canonical commands and labels
remaining legacy operations. Legacy `prime` retains its text and output contracts;
help names the replacement. API-backed commands keep their existing session path.

Added read-only `planka workflow claim-status` using the existing cross-board
claim and latest-handoff rules, with canonical JSON/errors and offline help.
Malformed required discovery, board, membership, identity, and comment records
fail safely. Legacy `loop-lock` retains its contracts; help names the replacement.

Isolated agent conventions and workflow operations under `Planka::Workflow`,
with explicit workflow loading and CLI attachment. Core resource loading no
longer implicitly loads workflow or CLI helpers; Ruby callers can explicitly
require `planka/workflow`. Historical Ruby paths, constant aliases, and
formatting forwarders are removed. Existing CLI entry points retain their contracts. Separate workflow gem packaging remains deferred.

Added read-only `planka workflow branch-name CARD` with canonical JSON/error
handling and offline help. It preserves legacy feature-label selection, title
slugging, truncation, and human output. Optional `PLANKA_BRANCH_PREFIX` is captured
once and validated before network access for this workflow. Legacy `branch-name`
and its direct executable retain their behavior; help names the replacement.

Added read-only `planka workflow pending-criteria CARD` and offline workflow help.
It preserves the `unticked` acceptance-criteria rules and human output, with
canonical JSON/error handling and explicit card IDs or same-instance URLs.
Empty criteria succeed; malformed required records fail clearly. Legacy
`unticked` and its direct executable retain their behavior; help names the
implemented replacement.

Separated canonical invocation parsing, configuration/reference validation, and
output/status handling from the command coordinator. Canonical sessions use
explicit validated settings, and readers report malformed response shapes as
`InvalidResponse`. Invalid authentication tokens fail before resource reads.
Legacy session/reader defaults and command contracts remain unchanged.


Added `planka describe board BOARD` (also `describe boards`) to read the existing
board snapshot through the canonical JSON/error and session contract. Explicit
board IDs or same-instance URLs are required; environment defaults do not replace
the target. Human output matches `snapshot --board`; legacy snapshot and its
`--list` mode retain their output. Malformed snapshot collections fail clearly.


Added `planka describe card CARD` (also `describe cards`) with nested help and
common `-o`/`--output` flags. Human output matches `show`; JSON uses the canonical
`data`/`meta`/`error` envelope. Input and required environment are validated
before authentication. API errors use stable codes and omit raw server bodies.

All 21 flat commands and direct executables are deprecated and retained
indefinitely with their existing arguments, effects, JSON, and exit behavior.
Help labels deprecation; there are no automatic runtime warnings. `show` has
an implemented replacement in `describe card`; the board view of `snapshot` has `describe board`;
`unticked` has `workflow pending-criteria`; other canonical operations
remain planned. Removal belongs to a separate track of work.

Added `planka prime` (also `planka-prime`) to print a concise, built-in agent
workflow guide without credentials or API access. Supports `--output json`.

Standardized help and diagnostic names on `planka <command>` while preserving
the direct `planka-*` executables. All commands list and support `-h`/`--help`
without credentials; top-level help points to command-specific help.

Added publishing and reading commands so an agent can create and verify specs
and tickets without the MCP server or ad hoc REST: `snapshot`, `show`,
`create-list`, `create-spec`, `create-ticket`, `update-card`, `move-card`,
`labels`, `create-label`, `apply-label`, `create-task-list` and
`rename-task-list`. Creates no longer retry once their outcome is unknown, so a
timeout cannot silently duplicate a card.

All commands now print human-readable results by default and accept
`--output json` for agents and scripts. The existing publishing-command JSON
documents remain unchanged when that flag is used; the earlier workflow
commands now expose structured JSON results as well.

## 0.1.0

Extracted Planka Ruby workflows from Lucenta; added configurable instance, board and branch prefix, gem packaging, and the `planka` command.
