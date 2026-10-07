# Changelog

## Unreleased

Added native card resource commands with singular/plural aliases and offline
root/group/leaf help: `get cards --board BOARD|--list LIST` (exact `--name`,
repeated AND `--label`/`--member`, `--limit`, complete reads that page archive
and trash lists), `get card CARD`, `create card --list LIST --name NAME`,
`update card CARD`, `move card CARD --list LIST`, and `delete card CARD`. Creates
use the board's default card type and append unless positioned; updates send
only supplied, changed name/description fields; moves stay on the card's board;
deletes issue one native deletion. Unknown outcomes report `readback-cards` or
`readback-card` recovery without retries or invented IDs. These replace legacy
`update-card`, `move-card`, and the list view of `snapshot`, which remain
available unchanged; their help names the replacements. Card operations live
under `Planka::Boards::Cards` and `CLI::Resources::Cards`. `Resource#create`
now takes validated attributes and a creation scope, create/update requests
receive the desired state, and catalog preparation receives the resolved
positional reference.

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
