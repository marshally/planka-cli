# CLI redesign implementation handoff

## State and intent

The goal is a general Planka administration CLI with a kubectl-like
`planka <verb> <resource> [reference] [flags]` interface. Convention-based agent
operations live under `planka workflow`.

The first slice is implemented: nested dispatch/help and `planka describe card
CARD`. The second slice adds `planka describe board BOARD`; the third adds
`planka workflow pending-criteria CARD`; the fourth adds
`planka workflow branch-name CARD`. All legacy entry
points are preserved. Other administration operations
remain planned. README's **Current interface** describes working commands; its
**Usage — planned interface** section describes the broader target.

Read [STYLEGUIDE.md](../STYLEGUIDE.md) for the design contract, including the full
legacy-to-canonical mapping, and [README.md](../README.md) for examples. This
handoff supplies implementation sequencing and verification requirements. It
does not imply that every resource supports every verb.

Start from the default branch after this documentation PR merges, or from the PR
head if implementation begins before merge. Inspect current branch, worktree,
dirty state, and remote refs before starting; this document is not a live status
record. Use an isolated implementation branch and preserve unrelated work.

## Code entry points

| Path | Role |
| --- | --- |
| [exe/planka](../exe/planka) | Flat command whitelist and executable dispatcher. |
| [exe/](../exe/) | Existing leaf parsers and direct `planka-<command>` entry points. |
| [lib/planka/cli.rb](../lib/planka/cli.rb) | Legacy option parsing, human formatters, scope helpers, and recovery/error plumbing. |
| [lib/planka/canonical_cli.rb](../lib/planka/canonical_cli.rb), [lib/planka/cli/](../lib/planka/cli/) | Canonical coordinator, parsed invocations, validated configuration, output/status handling, and expected failures. |
| [lib/planka/client.rb](../lib/planka/client.rb) | HTTP endpoints, session lifecycle, retries, and unknown-write-outcome detection. |
| [lib/planka/card_detail.rb](../lib/planka/card_detail.rb), [lib/planka/snapshot.rb](../lib/planka/snapshot.rb) | Existing detailed card and board/list read models. |
| [lib/planka/publishing.rb](../lib/planka/publishing.rb), [lib/planka/labels.rb](../lib/planka/labels.rb), [lib/planka/lists.rb](../lib/planka/lists.rb), [lib/planka/task_lists.rb](../lib/planka/task_lists.rb) | Existing publishing and resource operations. |
| [lib/planka/prime.rb](../lib/planka/prime.rb) | Built-in, credential-free agent guide. |
| [test/lib/planka/cli_test.rb](../test/lib/planka/cli_test.rb) | Subprocess help, argument, environment, and direct-executable checks. |
| [test/lib/planka/publishing_cli_test.rb](../test/lib/planka/publishing_cli_test.rb) | End-to-end subprocess commands against a local HTTP fake, including recovery. |
| [test/lib/planka/fake_planka.rb](../test/lib/planka/fake_planka.rb) | In-memory API test server; useful regression evidence, not proof of a real API contract. |
| [test/fixtures/files/planka/board.json](../test/fixtures/files/planka/board.json) | Captured board data used by domain tests. |
| [planka-cli.gemspec](../planka-cli.gemspec) | Packaged files, executable inventory, and Ruby requirements. |
| [Makefile](../Makefile), [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Test/build commands and CI Ruby matrix. |

The existing client already has board/card/comment reads, list-card reads,
creates for cards/lists/labels/task lists/tasks/comments, card/task-list updates,
card moves, and membership/label attachment. Inspect actual methods before
reusing them. Reading board IDs through the projects response does not establish
a complete project or board administration interface.

## Implemented first slice: nested dispatch and card detail

The first slice delivers `planka describe card CARD` using existing card-detail behavior,
along with root, `describe`, and leaf help. Keep every current command and direct
executable callable. This slice establishes command routing and compatibility
without requiring new API endpoints, configuration storage, or mutation behavior.

The first leaf's JSON schema and human output contract are recorded below. Canonical output uses the approved `data`/`meta`/`error`
envelope: put the existing card-detail object in `data`, with `meta: {}` and
`error: null` on success. Preserve the unwrapped legacy `show` JSON shape and test
the two contracts independently. Use the approved error/recovery rules in the
style guide and document the leaf's applicable error codes.

### First leaf output contract

`describe card CARD` returns the existing card-detail object in `data`, an empty
`meta` object, and `error: null`. Detail fields are `id`, `name`, `description`,
`type`, `boardId`, `listId`, `listName`, `position`, `url`, `labels`, `members`,
`taskLists`, `blockers`, and `comments`. Labels contain `id`/`name`; members are
user IDs; task lists contain `id`/`name`/`position`/`tasks`, whose fields are
`id`, `name`, `isCompleted`, `linkedCardId`, and `position` when available.
Blockers contain `cardId`/`taskId`/`completed`; comments contain
`id`/`text`/`userId`/`createdAt` when available. Missing optional scalar values
may be null; empty related collections are arrays.

Human output preserves the existing `show` rendering: name and URL, list,
labels, and nonempty description, members, task lists, blockers, and comments.
Failure JSON contains `data: null`, `meta: {}`, and an error with `code` and
`message`; this read-only leaf has no mutation recovery action. Exit 2 uses
`invalid_input`; exit 1 uses `configuration_error`, `authentication_error`,
`authorization_error`, `not_found`, `api_error`, or `network_error`. Failed
related reads do not claim a complete detail result. Diagnostic messages identify
the canonical command without exposing credentials or raw server response bodies.

### Acceptance criteria

- `planka describe card CARD` accepts current card IDs and supported card URLs,
  uses the existing environment/session mechanism, and reads the correct instance.
- It supports `--output human|json`, `-o json`, and `-h`/`--help`. Common output
  flags work before or after the command path. Do not add context/config flags.
  Missing or empty required environment variables fail before network access.
- Human output includes the current useful card details. JSON mode emits one
  documented document on stdout, with diagnostics only on stderr.
- Root and group help list implemented canonical commands with descriptions.
  Help and version work without credentials, network, or a repository checkout.
- Incomplete paths, unknown resources/verbs, extra arguments, and invalid flags
  fail clearly before authentication. No undocumented fallback treats a malformed
  nested command as another operation.
- `show CARD`, `planka-show CARD`, and all other legacy entry points retain their
  arguments, effects, and JSON contracts. Canonical help/diagnostic names may change
  as specified by the style guide; update existing name assertions deliberately.
- `describe card` performs no resource writes. Authentication session creation
  and cleanup are distinct from changing board data; assert that distinction in
  HTTP request expectations.
- Add subprocess tests for the nested invocation and meaningful legacy/canonical
  behavior equivalence, rather than tests that merely inspect dispatch tables.
- Update README to identify this slice as implemented while retaining planned
  labels for commands that are still unavailable. Do not label the entire redesign
  complete after one leaf ships.

Use focused red/green checks for the new invocation, then run:

```sh
bundle exec ruby -Ilib -Itest test/lib/planka/cli_test.rb
bundle exec ruby -Ilib -Itest test/lib/planka/publishing_cli_test.rb
bundle exec make ci
```

`make ci` runs all tests and builds the gem. Verify installed-gem canonical and
legacy help in an isolated install location; extraction into new files must not
leave them out of the package. Report local versus CI verification separately.

### Boundary

The first task adds no new deletion, relationship removal, user administration,
saved credentials, pagination, declarative apply, or API-version support.
Those are separate capabilities with their own API contracts and acceptance
criteria. Do not add command placeholders that claim these features work.

## Implemented second slice: board description

The second slice delivers `planka describe board BOARD` (alias `boards`) using the existing
board snapshot read. Accept numeric board IDs and same-instance `/boards/ID`
URLs; require the positional target even when `PLANKA_BOARD_ID` is set. Board
names/project lookup and explicit parent flags are outside this slice.

Success JSON has `data` containing `boardId`, `lists`, `cards`, `labels`,
`cardLabels`, `taskLists`, `tasks`, and `cardMemberships`; `meta` is `{}` and
`error` is null. Related arrays preserve snapshot records, while cards gain URLs
and sort by position. Human output matches legacy `snapshot --board BOARD`.
This is a detailed board read, not a paginated collection command: no
`meta.complete`, filters, or `--limit` are introduced. The endpoint supplies only
its included snapshot; do not claim completeness beyond that response.

Use the first leaf's canonical environment, JSON failure, exit, URL validation,
and session-cleanup rules, with board-specific help and diagnostics. Legacy
`snapshot` and `planka-snapshot` retain their arguments, human/JSON output, and
exit behavior, including their `--list` mode. Test at the established subprocess
and local HTTP seams: envelope/data/human equivalence, all entry points, request
boundaries, missing target/configuration, same-instance URLs, malformed payloads,
and API failures. No new endpoints are introduced; evidence remains the captured
board fixture and local HTTP fake, without live compatibility claims. Unexpected
collection types in the included snapshot fail as `api_error`. Missing optional
collections become empty arrays, preserving existing snapshot behavior.

## Implemented third slice: pending criteria

`planka workflow pending-criteria CARD` is a read-only migration of `unticked`.
Accept an explicit numeric card ID or same-instance `/cards/ID` URL, including
the configured instance path. There is no operation alias or board fallback.
The command requires `PLANKA_BASE_URL`, `PLANKA_AGENT_EMAIL`, and
`PLANKA_AGENT_PASSWORD`, validated before network access. Root, workflow-group,
and leaf help work offline and advertise only implemented workflow operations.

Success JSON is `{"data":{"cardId":"123","criteria":["Verify behavior"]},"meta":{},"error":null}`.
Criteria are unfinished tasks from every task list named exactly
`Acceptance criteria` on the target card, in board-response order, using the
existing `Card#unticked_criteria` rule. Other task lists and completed tasks are
excluded. No criteria list or all-completed criteria succeed with `criteria: []`.
Human output is one criterion per line, or a blank line for an empty result,
matching legacy `unticked`. This is workflow inspection, without collection
pagination, filtering, limits, or `meta.complete`.

The [PendingCriteria reader](../lib/planka/pending_criteria.rb) reads
`GET /api/cards/:id` for its board reference, then `GET /api/boards/:id` for the
existing included records. It shares `Board`/`Card` inspection logic with legacy
`unticked`. No comment read or resource writes are needed. API evidence is the
existing read path, captured fixtures, and local HTTP fake; no new endpoint or
live-version compatibility claim is introduced.

The card's board reference must be a numeric ID before any board request.
Malformed card board references, required board records, task-list identity/name
fields, and task names/completion flags fail as sanitized `api_error` with null
data and exit 1. Missing/invalid input, conflicting flags, unsupported flags, or
foreign-instance URLs fail as `invalid_input` with exit 2 before network access.
Missing configuration exits 1 as `configuration_error`. HTTP 401/403/404 map to
`authentication_error`/`authorization_error`/`not_found`; transport failures use
`network_error`. Sign-out failures preserve the read result and status and emit
a cleanup diagnostic. Failures do not provide partial criteria or retry writes.

`unticked` and `planka-unticked` retain their arguments, bare JSON, human output,
and exits indefinitely. Their help names the implemented replacement without
runtime warnings. Acceptance checks use the established subprocess/local HTTP
seams for legacy equivalence, task-list/completion conventions, empty success,
help, explicit references, pre-network validation, malformed records, API errors,
request boundaries, and cleanup preserving success.

## Implemented fourth slice: branch name

`planka workflow branch-name CARD` is a read-only migration of `branch-name`.
Accept an explicit numeric card ID or same-instance `/cards/ID` URL, including
the configured instance path. No board setting, operation alias, or parent
fallback is introduced. Root, workflow-group, and leaf help work offline.

Success JSON is `{"data":{"cardId":"123","branch":"card/fix-login"},"meta":{},"error":null}`.
Human output is the branch followed by a newline, matching legacy `branch-name`.
The existing `BranchName.for` algorithm selects the first `feature:` label in
board association order, otherwise uses `card/`; it slugs the title and applies
the existing word-boundary truncation. This slice does not change naming rules,
validate Git ref names, create a Git branch, or write to Planka resources.

The three required connection settings and target are validated before network
access. Optional `PLANKA_BRANCH_PREFIX` is captured once from the supplied
environment and reserves space in the 63-character budget. It is not prepended
to the branch. The existing rule requires at least eight characters of remaining
space; a prefix longer than 55 characters yields `configuration_error`, null
data, and exit 1 before authentication. This optional setting is validated only
for branch-name; unrelated canonical reads do not use it.

The [BranchName reader](../lib/planka/branch_name.rb) reads the card for its
numeric board reference and then reads the board's included records, reusing
`Board`/`Card` and the legacy naming algorithm. Required card/index fields and
label associations used for naming must be present and well shaped. Malformed
board references, titles, label records, or unresolved target-card labels yield
sanitized `api_error` with null data and exit 1. No comment read is required.
Input/configuration/HTTP/network/cleanup errors follow the pending-criteria
contract, including successful reads surviving sign-out failure.

`branch-name` and `planka-branch-name` retain their arguments, bare JSON, human
output, and exits indefinitely. Only help names the implemented replacement;
no runtime warning is added. Acceptance uses subprocess/local HTTP seams for
legacy equivalence, first-feature selection, slug/truncation/prefix behavior,
offline help, explicit references, pre-network validation, malformed records,
API failures, request boundaries, and cleanup. Evidence is existing read logic,
captured fixtures, and local HTTP tests, without new endpoints or live-version
compatibility claims.

## Canonical CLI architecture

The coordinator in [canonical_cli.rb](../lib/planka/canonical_cli.rb) follows
parse → validate → open session → execute → render. The executable alone exits
for canonical commands; the coordinator and output module return a status.
Legacy executables retain their existing argument/output adapters.

| Owner | Interface and responsibility |
| --- | --- |
| [CLI::Invocation](../lib/planka/cli/invocation.rb) | `parse` resolves command aliases, validates local syntax, and supplies help or an executable request. Command definitions select the reader and human formatter. |
| [CLI::Configuration](../lib/planka/cli/configuration.rb) | `from_env` validates and captures one invocation's settings; `resolve_reference` enforces the selected instance. Inspection redacts connection settings. |
| [CLI::Output](../lib/planka/cli/output.rb), [CLI::Failure](../lib/planka/cli/failure.rb) | Render canonical envelopes, human output, safe diagnostics, and statuses. Expected failures can carry known data/metadata. |
| [Client](../lib/planka/client.rb) | Own HTTP/session lifecycle. Accept explicit connection settings; canonical sessions opt into response-document and token validation. |
| [CardDetail](../lib/planka/card_detail.rb), [Snapshot](../lib/planka/snapshot.rb), [PendingCriteria](../lib/planka/pending_criteria.rb), [BranchName](../lib/planka/branch_name.rb) | `read(client, id, base_url:, ...)` returns canonical data and validates the response shapes each reader needs. BranchName additionally takes an explicit `prefix:`. |

Help runs before configuration or authentication. Canonical readers receive the
validated base URL explicitly; they do not fetch settings from the environment.
Invocation selects command-specific reader options from configuration before
the session opens, including the validated branch prefix when needed.
Malformed response documents, tokens, and required reader records raise
`Planka::InvalidResponse` near their consumption and become sanitized `api_error`
failures. Output does not disguise unexpected `TypeError`, `NoMethodError`, or
`KeyError` programming exceptions as server failures.

Legacy session/reader interfaces keep their default validation and coercion
behavior. Canonical reads opt into stricter shape checks. Missing optional board
snapshot collections still become empty arrays; card detail still fails if its
related board cannot supply the fields required by its index. Credentials remain
in memory and sign-out failures preserve the primary result. This restructuring
adds no new commands or endpoints.

## Subsequent implementation sequence

1. Migrate remaining existing reads and workflow inspection, then existing
   publishing and mutation operations, using the style guide's mapping. Share
   operation logic while keeping legacy argument and JSON adapters explicit.
2. Verify scope resolution and migrate input flags consistently: canonical
   `--name`, positional targets, parent flags, and `workflow resume ticket`.
   Preserve exact-name ambiguity errors and partial-write recovery.
3. Add new administration capabilities in independently reviewable slices:
   collection reads, deletion, relationship removal, and project/board/user
   management only where the supported API contract is established.
4. Verify environment validation and per-command session lifecycle across all
   canonical operations. Use project-supplied email/password, in-memory tokens,
   and sign-out cleanup; do not introduce persisted configuration or auth commands.
5. Reconcile README, built-in workflow guidance, executable packaging, and
   release notes with implemented behavior. Mark legacy help as deprecated under
   the retention policy below; do not add runtime warnings or remove entry points.

For every mutation slice, verify supplied-fields-only updates, idempotent
relationships where applicable, unknown outcomes, partial completion, and readback.
Do not rewrite retry behavior merely as a side effect of reorganizing commands.

## Settled decisions and implementation deliverables

The design decisions below are settled. Per-command schemas, error codes,
recovery actions, and API capability evidence remain deliverables of each
implementation slice; they do not reopen the shared contract.

JSON envelope and error/recovery rules are settled. Canonical commands always
include `data`, `meta`, and `error`; resource collections use arrays. Errors have
stable codes and readable messages, with recovery actions and known resource
references when applicable. Failures preserve known partial data or null;
mutation `meta.changed` is true, false, or null for an unknown effect. Legacy JSON
remains unchanged. See the style guide's Canonical JSON envelope section.
Per-command schemas, error codes, and recovery actions are implementation
deliverables governed by these rules, rather than an open envelope decision.

Exit codes are also settled: canonical commands return 0 for success, 2 for
invalid invocation/local input, and 1 for other failures, including incomplete
and unknown write outcomes. Detailed failure categories use JSON `error.code`.
Legacy exit behavior remains unchanged. See the style guide's Exit codes section
for category boundaries.

Configuration source is settled: each project supplies its own process
environment. Missing or empty required variables fail before network access.
Saved contexts, user-level config files, and fallback to another project are
excluded. Projects use the same `PLANKA_*` names with their own values; there are
no variable-name mappings or project-specific prefixes. Scope defaults are needed
only when the requested operation requires them and explicit references/parent
flags do not supply scope. Help, version, and the built-in guide remain
credential-free.

Authentication is settled: each API invocation signs in with
`PLANKA_AGENT_EMAIL` and `PLANKA_AGENT_PASSWORD`, holds the token in memory, and
attempts sign-out on completion. No persisted credentials, interactive prompts,
auth commands, or environment-token mode. Cleanup must not mask the operation
result/error; keep credentials bound to `PLANKA_BASE_URL`.

Pagination behavior is settled: collection reads fetch the complete scoped
collection by default, following supported API pages internally. `--limit N`
provides an explicit result cap. Collection JSON reports `meta.complete`; page
failures return nonzero and preserve collected data without claiming success.
Verify endpoint paging, ordering, and completeness during implementation; do
not infer support from this behavioral contract.

Filtering is settled: explicit applicable flags (`--name`, `--label`, `--member`)
combine with AND, including repeated labels/members. Names match exactly and
filters precede `--limit`. Verified server filters and client-side filtering must
produce equivalent results; `meta.complete` refers to matching results. No general
selector language or filter-based bulk mutations. Each capability must verify
endpoint paging, ordering, and filtering support during implementation.

The supported-version floor is settled: target Planka 2.0.0 and higher, with no
Planka 1.x API adapters. This minimum does not establish compatibility with every
later release or edition. Record verified versions and verb/resource capabilities
as implementation proceeds, and establish reliable version/capability detection
from API evidence. Future major releases require verification.

Deletion confirmation is settled: an explicit `delete RESOURCE REF` executes
without prompts or `--yes`, identically in terminals and scripts. Missing targets
are invalid invocation. Cascades follow native API behavior only: one target
delete mutation, no recursive client-side deletes, no dependency cleanup to
bypass restrictions, and no `--cascade` flag. Preserve server errors and document
resource-specific effects. Resolution reads and session lifecycle requests are
not additional resource deletions.

Legacy deprecation is settled: all 21 flat commands and their direct executables
are deprecated compatibility entry points, retained indefinitely. Preserve their
arguments, effects, JSON shapes, and exit behavior. Mark deprecation in
documentation and in help when help is updated, and describe implemented
replacements in release notes. Do not add automatic runtime warnings. There is
no removal release, deadline, or automatic expiration; any later sweep/removal
belongs to a separate, explicitly scoped track. The author is currently the only
gem user, so this decision imposes no external-consumer migration window. Never
present an unimplemented replacement as available. See the style guide
[Migration section](../STYLEGUIDE.md#migration-from-the-current-interface).

Do not choose a generic resource model or credential persistence scheme simply
because kubectl has one. Use Planka's actual model and this project's deployment
and unattended-call requirements.

## API evidence and acceptance limits

Existing tests cover captured board data and a local HTTP fake. The README notes
that API shapes were inherited from Lucenta and that compatibility with other
Planka releases has not been established. Passing these tests proves regression
behavior against those inputs; it does not prove every example works on a live
instance.

For each new capability, record the target edition/version, endpoint and payload
contract, evidence source, and observed read/write behavior. Use official API
documentation, accurately captured responses, or a real instance as appropriate.
Do not invent endpoint support from fake-server behavior. Collection reads must
also establish pagination and completeness.

For a write capability, create a bounded test resource on an authorized instance,
read it back, verify its intended effects, and clean it up within that scope.
Use sanitized fixtures and output; exclude credentials and unrelated board data.
If live verification is unavailable, state the exact coverage limit in the PR
instead of claiming live compatibility. Readback is particularly important after
timeouts or multi-step workflows.

## Upstream deletion evidence

Inspected the official Planka Community server source at tag `v2.2.1`. This is
source verification, not a live deletion test or proof for every 2.x release.
The REST delete controllers accept a target ID; these handlers do not offer a
generic cascade toggle. [Routes](https://github.com/plankanban/planka/blob/v2.2.1/server/config/routes.js)
map the commands to native DELETE endpoints.

| Target endpoint | Native behavior | Pinned server evidence |
| --- | --- | --- |
| `DELETE /api/projects/:id` | Refuses projects that still have boards; does not delete them to make the request succeed. | [Project helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/projects/delete-one.js) |
| `DELETE /api/boards/:id` | Deletes the board and its lists/cards, labels, memberships, and related board data on the server. | [Board cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/boards/delete-related.js), [list cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/delete-related.js) |
| `DELETE /api/lists/:id` | Deletes an eligible kanban list and moves its cards to the board's trash list. It does not permanently delete those cards. | [List controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/delete.js), [list helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/delete-one.js) |
| `DELETE /api/cards/:id` | Deletes the card and related task lists/tasks, attachments, comments, memberships, labels, subscriptions, and other card data. Clears linked-card references in other tasks instead of deleting those other cards. | [Card cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/delete-related.js) |
| `DELETE /api/task-lists/:id` | Deletes its tasks as part of server-side cleanup. | [Task-list cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/task-lists/delete-related.js) |
| `DELETE /api/labels/:id` | Removes card-label assignments; cards themselves remain. | [Label cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/labels/delete-related.js) |

The project nonempty restriction and list-to-trash behavior were also checked in
tags `v2.0.0` and `2.1.1`. Recheck permissions, response schemas, and effects on
the deployed version before implementing each delete capability. Test that a
project rejection issues no child deletions and that deleting a list preserves
the server's move-to-trash behavior. Do not assume a board deletion's internal
list cleanup is identical to the standalone list-delete endpoint.

## Resume checklist

1. Read the style guide, this handoff, and current README implementation labels.
2. Inspect current refs and source; do not assume this snapshot is still current.
3. Select the next unfinished slice; nested dispatch/help, card detail, board description, workflow pending criteria, and workflow branch name are complete.
4. Record that slice's schemas, error/recovery details, and API evidence; add
   meaningful failing acceptance tests, implement, and verify packaged entry points.
5. Update docs and report implemented capabilities, compatibility evidence,
   verification limits, and remaining work in the implementation PR.
