# CLI style guide

This document defines the target interface for a general Planka administration
CLI. It is a design contract for staged changes; the current executable supports
`describe card`, `describe board`, `workflow pending-criteria`, `workflow branch-name`,
`workflow claim-status`, and nested help alongside all flat commands in
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

The administration vocabulary follows Planka's native resources: projects,
boards, lists, cards, labels, task lists, tasks, comments, users, and memberships.
Only expose resource/verb combinations supported by the API. Specs and tickets
are convention-based card workflows and belong under `workflow`.

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
planka add member USER --card CARD
planka remove member USER --card CARD
planka create task-list --card CARD --name "Acceptance criteria"
planka update task-list TASK_LIST --name "Verification"
planka create comment --card CARD --text "Ready for review"
planka get comments --card CARD
planka delete comment COMMENT
```

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

The administration CLI targets Planka 2.0.0 and higher. Planka 1.x is outside
scope because the redesign targets the version-2 API contract; do not add legacy
API adapters or silently fall back to version-1 behavior.

The minimum version is a support boundary, not proof that all commands work on
every later release or edition. Record verified edition/version and supported
verb/resource combinations as capabilities are implemented. Future major
versions require API verification rather than an automatic compatibility claim.
Known unsupported versions or capabilities must fail clearly. Establish a
reliable version/capability check from the actual API contract; do not invent a
version endpoint or treat every API failure as proof of an old server.

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
The guide is built in and works without credentials, a checkout, or network.

General administrators can perform the primitive actions directly with
`add member`, `move card`, and `create comment` without adopting these conventions.

## Help and discoverability

Support help at every command level:

```sh
planka --help
planka create --help
planka create card --help
planka workflow --help
```

Root help groups administration and workflows.
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
