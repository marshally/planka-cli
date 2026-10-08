# CLI style guide

This document defines the target interface for a general Planka resource
CLI. It is a design contract for staged changes; the current executable supports
`describe card`, `describe board`, `workflow pending-criteria`, `workflow branch-name`,
`workflow claim-status`, `workflow guide`, `workflow next`, `workflow claim`,
`workflow resume ticket`, card-scoped `get members`, `get member`, `add member`, `remove member`, native card
`get cards`, `get card`, `create card`, `update card`, `move card`, `delete card`,
native list `get lists`, `get list`, `create list`, `update list`, `delete list`,
card task-list `get task-lists`, `get task-list`, `create task-list`,
`update task-list`, `delete task-list`, native label `get labels`, `get label`,
`create label`, `update label`, `delete label`, card-scoped `add label`/`remove label`,
and nested help alongside all flat commands in
README.md. Other examples below remain target syntax, not a claim that every
command is implemented or supported by every Planka release.

The [implementation handoff](docs/CLI_REDESIGN_IMPLEMENTATION.md) records code
entry points, staged implementation, acceptance criteria, and settled decisions.

## Command grammar

Use a kubectl-like verb/resource grammar:

```text
planka <verb> <resource> [reference] [flags]
planka workflow <operation> [arguments] [flags]
```

Use lowercase names, hyphens for multiword names, and spaces between command
levels. Do not introduce colon-separated task names or fuse verbs and resources
into names such as `create-card`. Keep nesting shallow and make the same verb
mean the same thing across resources.

The resource vocabulary follows Planka's native resources: projects,
boards, lists, cards, labels, task lists, tasks, comments, and users. Card membership
operations use `member`/`members` in the public CLI, describing a user assigned
to a card; the native membership is the relationship behind that vocabulary.
Only expose resource/verb combinations supported by the API. Specs and tickets
are convention-based card workflows and belong under `workflow`.

Resource commands read or change Planka resources and relationships directly.
Workflow commands apply project conventions to those resources, such as queue
selection, acceptance criteria, branch naming, and blocker handoffs. This
distinction describes behavior, not access permissions; each operation uses the
authenticated user's permissions in Planka.

## Verbs

| Verb | Syntax | Behavior |
| --- | --- | --- |
| `get` | `get RESOURCE [REF]` | List a collection or read one resource; concise output. |
| `describe` | `describe RESOURCE REF` | Read a detailed view including useful related data. |
| `create` | `create RESOURCE [flags]` | Create a new resource. |
| `update` | `update RESOURCE REF [flags]` | Change only the explicitly supplied fields. |
| `delete` | `delete RESOURCE REF` | Delete the referenced resource. |
| `move` | `move card CARD --list LIST` | Change a card's list, with optional position. |
| `add` | `add RELATION REF --PARENT PARENT` | Attach an existing resource. |
| `remove` | `remove RELATION REF --PARENT PARENT` | Detach a relationship without deleting its resource. |

Accept singular and plural resource spellings as aliases. A reference determines
whether `get` reads one resource; without a reference it lists a collection.
Document singular spellings for individual operations and plural spellings for
collection reads. Require a target for `describe`, `update`, and `delete`.
Do not interpret an omitted target as permission for a bulk mutation.

Reserve `apply -f FILE` for a future declarative interface with documented
identity, reconciliation, and deletion semantics. Attaching labels uses `add`,
not `apply`.

### Labels

Native label reads, creation, updates, deletion, and card-label relationships
are implemented. `get labels --board BOARD` and `create label --board BOARD
--name NAME --color COLOR [--position N]` require explicit board scope.
`get label LABEL`, `update label LABEL [--name NAME] [--color COLOR]
[--position N]`, and `delete label LABEL` require `--board` or `PLANKA_BOARD_ID`,
even for IDs: the verified Community v2.2.1 API has no individual label GET.
LABEL is an ID, exact name in that board, or same-instance `/labels/ID` CLI
reference URL; this does not imply a native label web page. An explicit board
wins over the default and lookup never falls back to another board.

Collections use all labels in the board snapshot, ordered by position then
numeric ID; exact `--name` filtering precedes positive `--limit`. Individual
names can be ambiguous and report candidate IDs. Unknown IDs or names in scope
fail with `not_found`. Malformed collections preserve validated matching data
with `meta.complete: false` and exit 1.

Creation always creates and defaults to appending, unlike legacy exact-name
reuse. Names must be nonblank and at most 128 UTF-16 units. Color must be one
of the native values in `create label --help`; position is finite and nonnegative.
Updates change only supplied fields and identical values are a no-op. These
commands do not clear name/color/position; existing unnamed labels are readable.
Planka may normalize positions and renumber neighbors without client writes.
Deletion issues one native label DELETE; Planka removes assignments and keeps
cards. `add label LABEL --card CARD` and `remove label LABEL --card CARD` derive
board scope from the card and preserve unrelated relationships. Already-satisfied
relationships succeed without a write. There are no client deletion sweeps.

The [README label contract](README.md#canonical-labels) defines human output,
field schemas, failure projections, and readback recovery. Writes use
`meta.changed: true|false|null` and never retry an uncertain result. Legacy
`labels`, `create-label`, and `apply-label` retain their runtime contracts.

### Collection completeness and pagination

Collection reads return the complete scoped collection by default. Follow API
pages internally where paging is supported; verify actual endpoint behavior
before claiming completeness. Do not expose page/cursor controls as the primary
CLI contract or require `--all` to fetch the complete result.

Offer `--limit N` as an optional positive-integer result cap. Invalid limits are
local input errors. Successful limited reads may return fewer than N items.
Collection JSON includes `meta.complete`: true when the entire matching
collection was returned, false when results are truncated or retrieval fails.
Reaching the limit does not itself prove truncation; establish whether more
matching results exist before reporting completeness. When `--limit` truncates
human output, include a readable truncation notice. Explicitly limited results
are successful; a page-fetch failure is not.

On page-fetch failure, exit 1, retain collected results in `data`, set
`meta.complete` to false, and emit a structured error. Never silently return a
successful partial collection. Pagination does not promise a consistent snapshot
if resources change while pages are fetched; document endpoint-specific ordering
and consistency limits. Apply filters before the result limit.

### Collection filtering

Use explicit flags such as `--name`, `--label`, and `--member` on collection
commands where those fields or relationships are meaningful. `--name` is an
exact match, not substring search or a regular expression. Labels and members
use the documented reference-resolution rules; ambiguous names are errors.

All filters combine with AND, including repeated `--label` and `--member`
values. A repeated label means the card must have every specified label; a
repeated member means it must include every specified member. Reject conflicting
duplicate scalar filters instead of silently selecting the last value.

```sh
planka get cards --board BOARD \
  --label enhancement \
  --label feature:search \
  --member USER \
  --name "Fix login" \
  --limit 20
```

This returns at most 20 cards with the exact name `Fix login`, both labels,
and the specified member. Filtering precedes `--limit`, and `meta.complete`
describes completeness of the matching collection, not the unfiltered scope.
Fetching an unfiltered page of 20 items and then filtering it is not equivalent.

Use verified server-side filters or client-side filtering with the same matching
behavior. Client-side filtering must inspect enough pages to fulfill the filtered
limit and establish completeness. Unsupported filters fail clearly rather than
being ignored. The initial contract has no general selector expression language,
OR syntax, or filter-based bulk mutations.

```sh
planka get projects
planka get boards --project PROJECT
planka get lists --board BOARD
planka get cards --list LIST
planka get card CARD -o json
planka describe board BOARD
planka describe card CARD
planka create list --board BOARD --name "Ready"
planka create card --list LIST --name "Fix login" --description-file description.md
planka update card CARD --name "Fix session expiry"
planka move card CARD --list LIST
planka delete card CARD
planka create label --board BOARD --name enhancement --color berry-red
planka add label LABEL --card CARD
planka remove label LABEL --card CARD
planka get members --card CARD
planka get member USER --card CARD
planka add member USER --card CARD
planka remove member USER --card CARD
planka create task-list --card CARD --name "Acceptance criteria"
planka update task-list TASK_LIST --name "Verification"
planka create comment --card CARD --text "Ready for review"
planka get comments --card CARD
planka delete comment COMMENT
```

### Card members

Implemented card-member commands use the same vocabulary for reads and writes:
`get members --card CARD`, `get member USER --card CARD`,
`add member USER --card CARD`, and `remove member USER --card CARD`.
A member is an existing user assigned to the specified card. A singular read
identifies the user, not a membership ID, and reports that user's assignment to
that card; collection reads report its assigned users. Results include user
identity and assignment metadata; a native membership ID may appear in JSON but
is not the positional reference. The precise fields are recorded in the
[current README](README.md#canonical-card-members) under the shared result contract.

These operations manage the user-card relationship without invoking the workflow
claim operation or moving the card. Membership still affects claimed/takeable
status under the existing workflow conventions. Adding an existing relationship and removing an absent one are
idempotent no-ops. Removing a member preserves both the user and card. Board-member and deferred
project-manager operations are separate slices below. See
[card members issue #21](https://github.com/marshally/planka-cli/issues/21).

### Board members

Planned board-member commands use `get members --board BOARD`,
`get member USER --board BOARD`, `add member USER --board BOARD --role editor|viewer`,
`update member USER --board BOARD`, and `remove member USER --board BOARD`.
`USER` identifies the account, not the membership ID. Require exactly one member
scope (`--card` or `--board`), never both. Board-member add requires an explicit
role. Viewer comment permission uses `--can-comment true|false`, default false
on add; reject that flag for editors. Updates accept role and viewer comment
permission, changing only supplied values and rejecting empty updates. Preserve
native role-transition effects and verify them during implementation.

Role updates follow native transition defaults: editor to viewer without
`--can-comment` sets viewer comment permission to false; an existing viewer retains
its permission when the flag is omitted. Changing to editor sets the native field
to null. Reject `--can-comment` when the resulting role is editor, including when
role is omitted and the existing member is an editor. Validate resolved role before
the resource write; do not translate these transitions into extra cleanup writes.

Board-member read objects contain `id` (user ID), `name`, nullable `username`,
`boardId`, `membershipId`, `role`, `canComment`, `createdAt`, and `updatedAt`.
Timestamps describe the membership and are nullable; `canComment` is the native
viewer comment permission and is null for editors. Join native membership records
with user identities. Individual data is one object; collection data is an array
of the same shape under the canonical envelope.

Board-member collections accept exact `--name NAME`, `--username USERNAME`, and
`--role editor|viewer` filters, combined with AND before `--limit`. Reject unsupported
filters, including `--can-comment` on reads, and conflicting scalar values.
Order by username, then display name, then user ID, using locale-independent
ordering with null usernames last. Filter before applying `--limit` and preserve
the shared completeness and partial-result contract.

Adding an existing board member with matching requested permissions succeeds as
an idempotent no-op. If permissions differ, report an actionable conflict and
preserve the membership; require `update member` rather than implicitly changing
access. For a viewer add without `--can-comment`, compare against the approved
false default, not the existing permission.

Board-member removal preserves the account and board but follows native cleanup
of that user's board/card subscriptions, card memberships, and task assignments;
issue only the native target removal, without client-side cleanup writes. Track
implementation and version-specific acceptance evidence in
[board members issue #36](https://github.com/marshally/planka-cli/issues/36);
these commands are not implemented.

### Project managers

Planned project-manager commands use `get project-managers --project PROJECT`,
`get project-manager USER --project PROJECT`,
`add project-manager USER --project PROJECT`, and
`remove project-manager USER --project PROJECT`. `USER` identifies the account;
this native relationship has no board editor/viewer role or permission-update
command. Keep project-manager work in its own ticket, separate from card/board
members, and defer it to the end of the project plan in
[issue #37](https://github.com/marshally/planka-cli/issues/37). Its remaining specification
and implementation are deferred; no project-manager commands are implemented.

### Task lists

Implemented task-list commands are card-scoped: `get task-lists --card CARD`,
`get task-list TASK_LIST`, `create task-list --card CARD --name NAME`,
`update task-list TASK_LIST --name NAME`, and `delete task-list TASK_LIST`.
`TASK_LIST` is an ID or an exact name within a known `--card`; Planka has no
task-list page URL, so URL references are rejected rather than invented. A
task-list ID alone determines its card, and explicit `--card`/`--board` parents
must agree with it.

Collections order by native position, then ID, from the card read and accept
exact `--name` before `--limit`. Creation always creates, appends unless
`--position N` is given, and sends only the name and position so native display
defaults apply; it implies no workflow task-list names. Updates accept only
`--name`, preserving tasks, completion, identity, position, and card, and reject
empty updates. Deletion issues the one native target deletion, which deletes the
list's tasks and keeps the card; the client deletes no tasks individually. The
[README task-list contract](README.md#canonical-task-lists) records fields,
recovery, and output; see [task lists issue #19](https://github.com/marshally/planka-cli/issues/19).

### Tasks

Planned task resource operations cover both ordinary checklist tasks and tasks
linked to another card: create, collection/individual read, update, and delete.
Collection reads support `get tasks --task-list TASK_LIST` and
`get tasks --card CARD`, requiring exactly one collection scope. Card-wide results
identify each task's containing task list. Individual reads use `get task TASK`.
Task collection filters are exact `--name NAME`, `--completed true|false`,
`--assignee USER`, and `--linked-card CARD`. Assignee means task assignment,
not card membership. Combine supplied filters with AND before `--limit`, resolving
references under the shared scope rules and rejecting conflicting scalar values.
Apply the shared collection completeness contract. Within a task list, order by
ascending task position. Card-wide reads order by ascending task-list position,
then task position; use IDs as deterministic tie-breakers at each level. Apply
filters before taking the first `--limit N` matching tasks in that order.

Task read data uses flat objects containing `id`, `cardId`, `taskListId`, `name`,
`position`, `isCompleted`, `assigneeUserId`, `linkedCardId`, `createdAt`, and
`updatedAt`. Assignee and linked-card IDs are null when absent; timestamps are
nullable. Resolve `cardId` through the containing task list. Do not embed related
user, task-list, or linked-card objects solely to expand names. Collection data is
an array of this shape and individual data is one object, under the canonical
envelope.

Creation uses `create task --task-list TASK_LIST` with exactly one of `--name NAME`
for an ordinary task or `--linked-card CARD` for a linked task. Reject both or
neither before network requests; no explicit task-type flag is introduced.
Linked-task creation is restricted to a linked card on the task's own board.
Resolve linked-card names by exact match on that board, and reject cross-board
IDs/URLs before the resource write. No separate linked-board scope flag is exposed.
Require native edit permission on the task's board and native access to the linked
card; preserve server restrictions without extra writes to that card. Reads still
report existing cross-board links as flat IDs rather than hiding native data.
Verify per-version support during implementation.
Ordinary task creation accepts optional `--completed true|false`, defaulting to
incomplete when omitted. Linked-task creation rejects this flag because completion
follows the linked card's native state.
Task creation accepts optional `--position N` and appends to the task list when
omitted. Positions are native ordering values, not row indexes, and must be finite
and nonnegative. Task updates accept `--position N` and preserve position when
omitted. Verify native ordering and append calculation during implementation.

Relocation uses `move task TASK --task-list TASK_LIST` for ordinary and linked tasks,
with optional `--position N`. Restrict the destination to another task list on the
same card; reject cross-card destinations. Append when changing lists without an
explicit position. Field updates do not accept `--task-list`; a move to the current
task list without a position is an idempotent no-op rather than an implicit reorder.

Ordinary task updates accept `--assignee USER` or mutually exclusive
`--clear-assignee`. Resolve the user within the task's board and require board
membership; clearing sends the native null value. Linked tasks reject assignee
changes. Task creation does not accept assignment flags; creating an assigned
ordinary task requires a separate update, avoiding an implicit multi-write create.
Ordinary tasks change completion through `update task TASK --completed true|false`;
reject other values. Linked tasks reject direct completion changes and follow the
linked card's native completion state.
Ordinary updates also accept `--name NAME`; names are nonempty and obey the
verified native length limit. Change only supplied fields and reject empty updates.
Linked tasks accept position updates only; their name and completion follow the
linked card, and neither task kind accepts replacement of `linkedCardId` through
update. Respect native restrictions rather than translating linked-task updates
into extra writes to the linked card.

`delete task TASK` deletes the selected ordinary or linked task, preserving its
containing card/task list and any linked card. Follow native deletion and shared
unknown-write/recovery rules without client-side cascades. Workflow blocker
commands remain convention-based operations over these resources. Track this
planned resource slice in [issue #34](https://github.com/marshally/planka-cli/issues/34);
no task resource commands are implemented.

### Users

The initial planned user-resource slice is read-only: `get users` and
`get user USER`. Account creation, updates, deletion, and credential changes are
deferred. Reads support the instance directory (`get users`, `get user USER`)
and explicit board scope (`get users --board BOARD`, `get user USER --board BOARD`).

Board-scoped reads select users with native board membership, not every related
user included in a board response. Preserve native permission failures without
silently falling back between scopes. User read objects contain only `id`, `name`,
and nullable `username`; collection and individual reads use the same shape under
the canonical envelope. Do not project account details or authentication secrets.

Positional user names match display names exactly within the selected directory
or board scope, rejecting ambiguity with candidate IDs. Username is not an
alternate positional-name match. Collections accept exact `--name NAME` and
`--username USERNAME`, combined with AND before `--limit`; reject unsupported
filters and conflicting scalar values. Reserve `me` in `get user me` for the
authenticated account; without board scope read it directly without directory
access, and with `--board` validate its board membership. A literal display name
`me` remains available through `get users --name me`. Order user collections by
username, then display name, then ID, using
locale-independent ordering with null usernames last. Filter before applying
`--limit`; use the shared completeness and partial-result contract. Track this
planned read-only slice in
[issue #35](https://github.com/marshally/planka-cli/issues/35); no user commands
are implemented.

### Basic board creation and updates

Planned `create board --project PROJECT --name NAME` creates a board in the
specified project. Planned `update board BOARD` accepts `--name NAME` and
`--position N`, changes only supplied fields, and rejects empty updates. Names
are nonempty and obey the verified native length limit; positions are finite,
nonnegative native ordering values. Keep the board in its current project.
Defer imports, display settings, card-type defaults, and subscription management.
Creation accepts optional `--position N` and appends to the project when omitted;
updates preserve position when omitted. Verify native ordering and append
calculation during implementation. Track the resource slice in
[boards issue #22](https://github.com/marshally/planka-cli/issues/22); basic
create/update commands are not implemented.

### Basic project creation and updates

Planned `create project --name NAME` accepts optional `--type private|shared`,
default private when omitted. Type selection is creation-only; no implicit
ownership-transfer update. Names are nonempty and obey the verified native length
limit. Creation may omit description; preserve the native no-description state.

Creation and updates accept mutually exclusive `--description TEXT` or
`--description-file FILE`, with `--description-file -` reading stdin. Updates also
accept mutually exclusive `--clear-description`, sending native null; reject clear
on creation. Nonempty descriptions obey the verified native length limit; reject
empty input rather than interpreting it as clearing. Read/validate description
inputs before network requests and do not silently truncate them.

Planned `update project PROJECT` accepts `--name` and the description inputs
above, changing only supplied fields, preserving omitted description, and rejecting
empty updates. Defer ownership transfers, backgrounds, visibility, and favorites.
Preserve native project creation's own manager/owner effects without extra
client-side manager writes; this does not bring deferred project-manager commands
into scope. Track the resource slice in
[projects issue #23](https://github.com/marshally/planka-cli/issues/23); basic
create/update commands are not implemented.

### List updates

Implemented `update list LIST` accepts optional `--name`, `--color` or mutually
exclusive `--clear-color`, `--position`, and `--type active|closed`. Change only
supplied fields and reject empty updates. Names are nonempty and obey the verified
server length limit; colors use the verified native enum, `--clear-color` sends
null, and positions are finite and nonnegative. Keep the list on its current board.
Type changes preserve native server effects; document and test their effect on
linked tasks and workflow eligibility without additional client-side card/task
writes. See [lists issue #18](https://github.com/marshally/planka-cli/issues/18)
for the accepted field contract, and the [README lists
contract](README.md#canonical-lists) and implementation handoff for implemented
behavior and pinned version-specific evidence.

## References and scope

- Put existing targets in positional arguments: `update card CARD`, not
  `update card --id CARD`.
- Express parent scope with `--project`, `--board`, `--list`, and `--card`.
  Express a relationship's parent in the same way: `add label LABEL --card CARD`.
- Accept IDs and supported Planka resource URLs. Treat numeric references as
  IDs; do not silently reinterpret an unknown ID as a name.
- Resolve names by exact match within a known parent scope. Reject ambiguous
  matches and report candidate IDs. Never select the first match arbitrarily.
- Validate that explicit parents agree with each other and with a referenced
  resource. Explicit scope mismatches are errors.
- An ID or URL identifying a resource determines its actual parent. An environment-default
  board must not redirect an explicit card reference to another board.
- Require sufficient scope for collection reads and creates; do not silently
  aggregate all projects or boards. Operations intentionally spanning boards,
  such as workflow claim status, must document that scope.

Use `--name` for the displayed name of a resource, including cards, specs, and
tickets. Use `--text` for comments and `--description-file` for descriptions.
Retain API-specific terms only when they help users understand the operation.

## Supported Planka versions

The resource CLI targets Planka 2.0.0 and higher. Planka 1.x is outside
scope because the redesign targets the version-2 API contract; do not add legacy
API adapters or silently fall back to version-1 behavior.

The minimum version is a support boundary, not proof that all commands work on
every later release or edition. Record verified edition/version and supported
verb/resource combinations as capabilities are implemented. Future major
versions require API verification rather than an automatic compatibility claim.
Known unsupported versions or capabilities must be documented clearly. Verify
capabilities from the actual API contract; do not invent a version endpoint or
treat every API failure as proof of an old server. The diagnostic lookup below
does not gate execution or establish edition/capability support.

Planned canonical version lookup runs only after a primary Planka API,
authentication, network, or response-validation failure, using a read-only
bootstrap request. Do not add a version preflight to successful calls.
Help and offline commands skip lookup, and legacy requests/output stay unchanged.
Validate required configuration before any network request. Reported version is
not proof of edition or capability; do not probe support with resource mutations.
Version lookup is best-effort and runs at most once for a failed invocation.
Preserve the original error code/message, exit status, data, recovery information,
and existing metadata (including changed/unknown outcomes). Add
`meta.serverVersion` containing a well-formed reported semantic version, or null
when lookup fails or the version is absent/malformed. Successful commands and
local/configuration/dependency failures receive no diagnostic field or request,
even if earlier resolution reads succeeded. An API attempt alone is not a trigger.
Lookup failure cannot replace the primary error or trigger recursive
lookup/retry, and must not bypass session cleanup.

Human failures may append a reported-version line when available, retaining the
primary error; never print raw bootstrap bodies or classify compatibility from
version alone. A reported version below the target floor remains diagnostic
context rather than a replacement error. Keep edition/capabilities unknown unless
separately verified, and do not add persisted caches, mutating probes, or API
fallback adapters. Track the planned diagnostic slice in
[issue #32](https://github.com/marshally/planka-cli/issues/32); lookup is not implemented.

## Flags and input

Use consistent long flags across resources. Reserve `-h` for `--help` and `-o`
for `--output`. Accept common flags after the executable or command path, so
`planka -o json get cards --board BOARD` and
`planka get cards --board BOARD -o json` agree.

Descriptions accept `--description-file PATH`; criteria accept
`--criteria-file PATH` as a JSON array of strings. Both accept `-` for stdin.
Preserve newlines, Unicode, and quotes. Reject commands requesting multiple
independent inputs from the same stdin stream.

Reject unknown flags, extra positional arguments, conflicting inputs, invalid
values, and updates with no supplied changes. Validate local input before
opening an authenticated session or attempting a write. Omitted fields remain
unchanged; empty strings and explicit clearing must have documented semantics.

For creates and moves, append to the destination by default. `--position N`
overrides that behavior where the API supports positioning.

## Configuration and authentication

Each project supplies connection settings, credentials, and its own scope
defaults through the process environment. There is no saved context, current
context, user-level config file, `--context`, `--config`, or `planka config`
command. Do not reuse configuration from another project or silently fall back
to a different server or board.

Fail fast when required environment variables are missing or empty, before any
network request. Identify missing variable names without printing secret values.
Validate the complete required environment for the requested operation before
opening a session. Help, version, and the built-in workflow guide remain exempt.
Scope requirements depend on the operation: an explicit card reference determines
its parent; collection reads and creates need their documented parent scope.
Explicit parent flags may select scope but must not bypass required connection
and credential environment checks.

Use the same `PLANKA_*` variable names across projects, with project-specific
values supplied by the caller. Preserve `PLANKA_BASE_URL`, `PLANKA_AGENT_EMAIL`,
`PLANKA_AGENT_PASSWORD`, `PLANKA_BOARD_ID`, and `PLANKA_BRANCH_PREFIX`. Do not
introduce variable-name mappings or per-project prefixes. Connection and
authentication settings are required for API operations; scope defaults are
required only when the operation needs that scope and no explicit parent or
resource reference supplies it. An optional setting may be absent; do not invent
a required board for a command that derives it from a card.

Each API invocation authenticates with `PLANKA_AGENT_EMAIL` and
`PLANKA_AGENT_PASSWORD`, keeps its session token only in memory, and attempts
sign-out on completion, including operation failure. Credentials and tokens are
not persisted. There are no `planka auth` commands, interactive authentication
prompts, or externally supplied-token mode. Validate credentials before the
first network request; session cleanup must not mask the primary operation's
result or error. Document cleanup failures without claiming they undo writes.

Help and version output require no credentials or network. Environment
diagnostics must not reveal passwords or tokens. Authentication is scoped to the
selected server; never send credentials to a different server because a resource
URL was supplied. Do not read credentials from another checkout or invoke a
credential wrapper implicitly. All authentication is unattended and uses only the caller-supplied
environment. Ordinary resource commands must not prompt for login.

## Output and errors

- Default collection reads to readable tables containing IDs and useful names.
  Default individual reads and mutations to concise fields/results.
- `describe` expands related information such as labels, task lists, blockers,
  and comments. It is read-only.
- Support `-o json` and `--output json` consistently, including workflow commands.
  Emit one JSON document on stdout, without progress messages or banners.
- Define and document each command's JSON schema. Keep collection shapes stable
  for empty, one-item, and many-item results. Treat incompatible schema changes
  as compatibility changes; human formatting is not an automation interface.
- Mutation results identify the affected resource or relationship and indicate
  whether an operation changed anything. Provide resulting resource data when
  available, and preserve created IDs if later steps fail.
- Send diagnostics to stderr. Exit zero for success, including empty collections
  and already-satisfied idempotent relationships. Exit nonzero for invalid input,
  missing individual resources, authentication/API failures, and incomplete writes.
- Expected failures report the command, cause, and a concrete recovery action
  where available. Do not print a Ruby backtrace by default or disclose secrets.

An empty queue is a successful workflow result, not an API failure. JSON output
must distinguish an empty result from a failed operation.

### Exit codes

Canonical commands use these exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Success, including empty collections/queues and already-satisfied relationships. |
| `2` | Invalid invocation or local input: unknown commands/flags, incorrect arguments, invalid values, unreadable input files, or malformed input documents. |
| `1` | Other failures, including configuration, authentication, authorization, missing individual resources, API/network failures, incomplete writes, and unknown write outcomes. |

Use JSON `error.code` for finer failure distinctions rather than assigning a
separate process exit code to every error category. Missing required command
arguments are invalid invocation; missing credentials or unresolved required
configuration are operational failures. Ambiguous or absent names discovered
through API lookup are operational failures, rather than local syntax errors.
Legacy commands and direct executables retain their existing exit behavior.

### Canonical JSON envelope

Canonical commands use a shared envelope with `data`, `meta`, and `error`:

```json
{
  "data": {"id": "123", "name": "Fix login"},
  "meta": {},
  "error": null
}
```

Resource reads put the resource object in `data`. Collection reads put an array
in `data`, including `[]` for an empty collection. `meta` is an object for command
metadata; successful mutations include `meta.changed` to distinguish a change
from an already-satisfied operation. Successful commands set `error` to null.
Always include all three top-level fields, on success and failure. Failures retain
known partial results in `data`; use null when there are no known results.
`meta.changed` is true when an effect is known to have occurred, false when the
operation is known to have made no change, and null when the effect is unknown.
Do not infer false from a failed request. The overall outcome of a multi-step
workflow is distinct from whether any step changed data.

On failure, `error` is an object containing a stable machine-readable `code` and
a human-readable `message`. When recovery applies, it also contains `recovery`,
an object with an `action` and a `resources` array of known resource references.
Each reference identifies its resource `type` and `id`; never invent an ID after
an uncertain create. The array may be empty when the affected resource is unknown.
Recovery actions and per-command partial-result shapes must be documented.

```json
{
  "data": {"card": {"id": "123", "name": "Fix login"}},
  "meta": {"changed": true},
  "error": {
    "code": "partial_failure",
    "message": "Ticket created, but acceptance criteria are incomplete",
    "recovery": {
      "action": "resume-ticket",
      "resources": [{"type": "card", "id": "123"}]
    }
  }
}
```

Error codes are stable identifiers, not text to parse from `message`. An unknown
write outcome must expose that uncertainty and readback recovery rather than
suggesting an unconditional retry. Required per-command schemas and recovery
actions are specified as each capability is implemented under this envelope.

Workflow result schemas must fit this envelope and be documented individually.
Legacy commands retain their existing JSON shapes; this envelope applies to the
new canonical commands rather than retroactively wrapping legacy output.

## Mutation and recovery behavior

Make reads strictly read-only. `get`, `describe`, help, and workflow inspection
must not repair, comment on, move, or otherwise mutate resources.

`create` means create, unless a particular workflow explicitly documents reuse.
Do not silently turn a generic create into an upsert. `add` and `remove` should
succeed when the requested relationship already has the desired state.
An update touches only supplied fields.

Do not blindly retry a create or another write after a timeout with an unknown
outcome. Report that uncertainty and tell the caller how to read back and
reconcile. For multi-step workflows, preserve completed steps and created IDs in
JSON recovery output. Do not claim atomicity when the API uses multiple writes.
Provide an explicit resume operation instead of requiring a duplicate create.

Delete requires an explicit resource reference and executes without confirmation
prompts. The same invocation behaves identically in terminals and scripts; do
not require `--yes` or an interactive session. An omitted target is an input error,
not a request to delete a collection. Follow the target API's native delete
behavior and document its cascading effects and restrictions in help and errors.
Issue only the target resource delete; never recursively delete children,
implement cleanup cascades in the client, or bypass a server restriction by
deleting dependencies. There is no `--cascade` flag. Resolution reads and session
authentication/cleanup are separate from the single target mutation.

Native behavior is resource-specific: a list deletion may move cards rather than
delete them, and a project deletion may require an empty project. Preserve those
semantics rather than imposing a generic parent/child deletion model. See the
handoff's pinned upstream deletion evidence; verify the deployed release during
implementation.

## Workflow commands

Keep convention-based behavior under `workflow`. Document required list names,
label conventions, acceptance criteria, blocker representation, and any GitHub
CLI dependency in this namespace's help.

```sh
planka workflow guide
planka workflow create spec --list LIST --name "Search" --description-file spec.md
planka workflow create ticket --list LIST --name "Index documents" --criteria-file criteria.json
planka workflow resume ticket CARD --criteria-file criteria.json
planka workflow next --board BOARD --label feature:search
planka workflow claim CARD
planka workflow claim-status
planka workflow branch-name CARD
planka workflow pending-criteria CARD
planka workflow add blocker BLOCKER --card BLOCKED
planka workflow remove blocker BLOCKER --card BLOCKED
planka workflow complete-specs
```

`claim` combines membership and moving a card into progress. `claim-status`
reports existing claims; it does not acquire a lock. `complete-specs` comments
and moves eligible specs to done, and its help must state those writes.
`guide`, `next`, `claim-status`, `branch-name`, and `pending-criteria` are read-only.

Implemented `workflow claim CARD` uses an explicit ID or same-instance card URL
and the unique `in-progress` list on that card's board. Existing membership is
retained; a card already in that list is not moved or repositioned. It retains
other members and acquires no exclusive lock. Membership is added before the
move; an already-satisfied claim performs no resource writes. Moves request
native position 65535 and report the returned position. See
[the claim schema and recovery contract](README.md#canonical-claim) for data,
changed/uncertain outcomes, error codes, and readback recovery.
The guide is built in and works without credentials, a checkout, or network.

Implemented `workflow resume ticket CARD --criteria-file FILE|-` fills the missing
criteria of an existing ticket without creating a card. It reuses the card's one
`Acceptance criteria` list (creating it when absent), keeps existing criteria's
completion, text, and order, and appends missing ones in file order. Duplicate
criteria lists fail before writes. Failures keep known IDs and recover with
`resume-ticket`; see [the resume contract](README.md#canonical-resume-ticket).
Workflow commands may use three-word paths such as `workflow resume ticket`.

Implemented `workflow next` accepts `--board BOARD`, falling back to
`PLANKA_BOARD_ID` only when omitted. Repeated `--label` filters AND-match before
selection. At most one distinct `feature:` or `effort:` label selects the mode;
other labels narrow priority/feature/frontier candidates, including specs/maps.
Multiple mode labels fail before network access. With no mode label, select by
ready-for-agent priority. Empty or unknown-label matches succeed without a card.
This workflow returns a pick/waiting/frontier report rather than a paginated
resource collection; it has no `--limit` or `meta.complete`.
Selected priority/feature blockers use recorded handoffs and `gh` PR lookup for
stacking metadata. Failed lookups stay unknown; missing `gh` is configuration
failure, and malformed successful responses are API errors. See the
[next-work contract](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work).

Users can perform the primitive actions directly with
`add member`, `move card`, and `create comment` without adopting these conventions.

## Help and discoverability

Support help at every command level:

```sh
planka --help
planka create --help
planka create card --help
planka workflow --help
```

Root help groups commands under `Resource commands` and `Workflows`. These are
behavioral categories, not permission levels; neither heading implies a
requirement for administrator privileges.
Group help lists supported resources or operations with short descriptions.
Leaf help includes usage, required scope, arguments, defaults, flags, examples,
output behavior, and mutation/recovery behavior. Render the canonical command
name even when invoked through a compatibility alias.

Retain `planka --version`. No arguments prints root help successfully. Incomplete
command paths and unknown commands report useful help and fail without network
access. Show canonical commands in examples instead of an ungrouped list of aliases.

## Migration from the current interface

All 21 current flat commands and their direct `planka-<command>` executables are
deprecated compatibility entry points in the target contract. Retain them
indefinitely; this redesign has no removal release, deadline, or automatic
expiration. Any future removal belongs to a separate, explicitly scoped track of
work. The gem currently has only its author as a user; no external-consumer
migration window is required by this decision.

Preserve legacy arguments, effects, JSON shapes, and exit behavior while these
entry points remain available. Translate old arguments internally; do not make
an alias require the new flags or adopt the canonical JSON envelope/exit codes.
Mark the legacy interfaces as deprecated in documentation and, when command help
is updated during implementation, in help with links or names for implemented
replacements. Use release notes to describe the migration as replacements ship.
Do not add automatic runtime deprecation warnings or change stdout, stderr, or
exit codes merely to announce deprecation. Never direct users to a replacement
as a working command before it is implemented.

| Current command | Canonical target |
| --- | --- |
| `prime` | `workflow guide` |
| `snapshot` | `describe board BOARD`, or `get cards --list LIST` for a list read |
| `show CARD` | `describe card CARD` |
| `labels` | `get labels --board BOARD` |
| `create-list` | `create list` |
| `create-label` | `create label` |
| `create-task-list CARD` | `create task-list --card CARD` |
| `rename-task-list --id ID` | `update task-list ID --name NAME` |
| `update-card CARD` | `update card CARD` |
| `move-card CARD` | `move card CARD` |
| `apply-label CARD --label LABEL` | `add label LABEL --card CARD` |
| `comment CARD TEXT` | `create comment --card CARD --text TEXT` |
| `create-spec` | `workflow create spec` |
| `create-ticket` | `workflow create ticket` |
| `create-ticket --card CARD` | `workflow resume ticket CARD` |
| `next-card [LABEL]` | `workflow next --label LABEL` |
| `claim CARD` | `workflow claim CARD` |
| `loop-lock` | `workflow claim-status` |
| `branch-name CARD` | `workflow branch-name CARD` |
| `unticked CARD` | `workflow pending-criteria CARD` |
| `link BLOCKED BLOCKER...` | `workflow add blocker BLOCKER... --card BLOCKED` |
| `spec-sweep` | `workflow complete-specs` |

Translate legacy `--title` to canonical `--name`. Preserve existing JSON shapes
for legacy entry points. Canonical commands may introduce documented schemas.
A board description and card collection do not automatically reproduce the
legacy snapshot schema; the snapshot alias must retain that behavior.

New help and documentation use canonical names once those commands exist. Keep
README examples aligned with actual implementation rather than replacing them
with unimplemented target syntax. Deprecation does not authorize removal or
changes to the legacy JSON/exit contracts.
