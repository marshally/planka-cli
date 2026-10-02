# CLI style guide

This document defines the target interface for a general Planka administration
CLI. It is a design contract for future changes; the current executable still
uses the flat commands documented in README.md. Examples below are target
syntax, not a claim that every command is implemented or supported by every
Planka release.

The [implementation handoff](docs/CLI_REDESIGN_IMPLEMENTATION.md) records code
entry points, staged implementation, acceptance criteria, and open decisions.

## Command grammar

Use a kubectl-like verb/resource grammar:

```text
planka <verb> <resource> [reference] [flags]
planka workflow <operation> [arguments] [flags]
planka config <operation> [flags]
planka auth <operation> [flags]
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
- An ID or URL identifying a resource determines its actual parent. A default
  context board must not redirect an explicit card reference to another board.
- Require sufficient scope for collection reads and creates; do not silently
  aggregate all projects or boards. Operations intentionally spanning boards,
  such as workflow claim status, must document that scope.

Use `--name` for the displayed name of a resource, including cards, specs, and
tickets. Use `--text` for comments and `--description-file` for descriptions.
Retain API-specific terms only when they help users understand the operation.

## Flags and input

Use consistent long flags across resources. Reserve `-h` for `--help` and `-o`
for `--output`. Accept common flags after the executable or command path, so
`planka --context home get cards` and `planka get cards --context home` agree.

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

Provide named contexts for the server and default project/board scope:

```sh
planka config set-context home --server https://planka.example.com --project PROJECT --board BOARD
planka config get-contexts
planka config use-context home
planka get cards --context home
planka auth login
planka auth status
planka auth logout
```

Resolve settings in this order: explicit flags, process environment, selected
context, documented built-in defaults. `--context` selects a context without
changing the saved current context. Preserve the existing `PLANKA_*` environment
interface during migration. Workflow-specific defaults, such as a branch prefix,
must not affect ordinary administration commands.

Help and version output require no credentials or network. Configuration
inspection must not reveal passwords or tokens. Authentication is scoped to the
selected server; never send credentials to a different server because a resource
URL was supplied. Do not read credentials from another checkout or invoke a
credential wrapper implicitly. Login must support unattended callers without
forcing an interactive prompt; ordinary resource commands must not prompt for
login.

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
Failures use a structured `error`, including recovery information for incomplete
writes. Exact error/recovery fields remain to be settled before implementation.

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

Delete requires an explicit resource reference. Document cascading effects in
command help and errors. If confirmation is required for a particular destructive
operation, provide `--yes` for automation and fail clearly in noninteractive mode
without it; never block a script on an unexpected prompt.

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

Root help groups administration, workflows, configuration, and authentication.
Group help lists supported resources or operations with short descriptions.
Leaf help includes usage, required scope, arguments, defaults, flags, examples,
output behavior, and mutation/recovery behavior. Render the canonical command
name even when invoked through a compatibility alias.

Retain `planka --version`. No arguments prints root help successfully. Incomplete
command paths and unknown commands report useful help and fail without network
access. Show canonical commands in examples instead of an ungrouped list of aliases.

## Migration from the current interface

The redesigned contract does not immediately remove existing commands or direct
`planka-<command>` executables. Keep them as compatibility entry points with their
existing argument conventions until a documented deprecation/removal release.
Translate old arguments internally; do not make an alias require the new flags.

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
for legacy entry points unless a separately documented compatibility change is
made. Canonical commands may introduce documented schemas. A board description
and card collection do not automatically reproduce the legacy snapshot schema;
the snapshot alias must retain that behavior.

New help and documentation use canonical names once those commands exist. Keep
README examples aligned with actual implementation rather than replacing them
with unimplemented target syntax. Announce alias deprecations and schema changes
before removing them.
