# CLI redesign implementation handoff

## State and intent

The goal is a general Planka resource CLI with a kubectl-like
`planka <verb> <resource> [reference] [flags]` interface. Convention-based agent
operations live under `planka workflow`.

Public documentation and root help call direct resource operations “resource
commands,” distinct from convention-based workflows. These are behavioral
categories, not permission levels. `CLI::Resources` owns the internal
resource-command catalog.

The first slice is implemented: nested dispatch/help and `planka describe card
CARD`. The second slice adds `planka describe board BOARD`; the third adds
`planka workflow pending-criteria CARD`; the fourth adds
`planka workflow branch-name CARD`; the fifth adds
`planka workflow claim-status`; the sixth adds
`planka workflow guide`; the seventh adds
`planka workflow next`; the eighth adds `planka workflow claim CARD`; the tenth
adds native card `get`, `create`, `update`, `move`, and `delete`; the eleventh
adds native list `get`, `create`, `update`, and `delete`; the twelfth adds
`planka workflow resume ticket CARD`; the thirteenth adds card task-list `get`,
`create`, `update`, and `delete`. Native label operations and comment
`get`, `create`, `update`, and `delete` are also implemented. Native boards (#22)
and projects (#23) support collection/individual reads, creation, updates, and
deletion. `planka workflow create spec` (#26) publishes project cards without
acceptance criteria. All legacy entry
points are preserved. Other resource operations
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
| [lib/planka/client.rb](../lib/planka/client.rb) | HTTP endpoints, session lifecycle, and unknown-write-outcome detection; every request is sent once. |
| [lib/planka/cards/detail.rb](../lib/planka/cards/detail.rb), [lib/planka/boards/snapshot.rb](../lib/planka/boards/snapshot.rb) | Existing detailed card and board/list read models. |
| [lib/planka/workflow/publishing.rb](../lib/planka/workflow/publishing.rb), [lib/planka/labels.rb](../lib/planka/labels.rb), [lib/planka/lists.rb](../lib/planka/lists.rb), [lib/planka/task_lists.rb](../lib/planka/task_lists.rb) | Existing publishing and legacy resource operations; legacy `create-list` uses `Lists`, canonical lists use `Boards::Lists`; legacy `create-task-list`/`rename-task-list` use `TaskLists`, canonical task lists use `Cards::TaskLists`. |
| [lib/planka/workflow/prime.rb](../lib/planka/workflow/prime.rb) | Built-in, credential-free agent guide. |
| [test/lib/planka/cli_test.rb](../test/lib/planka/cli_test.rb) | Subprocess help, argument, environment, and direct-executable checks. |
| [test/lib/planka/publishing_cli_test.rb](../test/lib/planka/publishing_cli_test.rb) | End-to-end subprocess commands against a local HTTP fake, including recovery. |
| [test/lib/planka/fake_planka.rb](../test/lib/planka/fake_planka.rb) | In-memory API test server; useful regression evidence, not proof of a real API contract. |
| [test/fixtures/files/planka/board.json](../test/fixtures/files/planka/board.json) | Captured board data used by domain tests. |
| [planka-cli.gemspec](../planka-cli.gemspec) | Packaged files, executable inventory, and Ruby requirements. |
| [Makefile](../Makefile), [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Test/build commands and CI Ruby matrix. |

The existing client already has board/card/comment reads, list-card reads,
creates for cards/lists/labels/task lists/tasks/comments, card/task-list updates,
card moves, and membership/label attachment. Inspect actual methods before
reusing them. Native project operations now have their own interface below;
legacy board discovery through the projects response remains unchanged.

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

The first task adds no new deletion, relationship removal, user-management
operations, saved credentials, pagination, declarative apply, or API-version support.
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

The [PendingCriteria reader](../lib/planka/workflow/pending_criteria.rb) reads
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

The [BranchName reader](../lib/planka/workflow/branch_name.rb) reads the card for its
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

`Board.included_for_card(client, id)` owns the shared validated card-to-board
lookup for both workflow readers. Criteria and naming-specific validation stay
with their readers; legacy construction and adapters retain their defaults.

## Implemented fifth slice: claim status

`planka workflow claim-status` is a read-only migration of `loop-lock`. It accepts
no positional target, scope flag, or alias. The three connection settings are
validated before authentication. `PLANKA_BOARD_ID` and `PLANKA_BRANCH_PREFIX`
do not restrict or configure this inspection. Root, workflow, and leaf help
work without credentials or network access.

Success without an eligible card is
`{"data":{"held":false,"card":null},"meta":{},"error":null}`. When held, data has
`held: true`, `card: {id, name, url}`, `claimedAt` as the existing ISO timestamp,
and integer `ageSeconds` using the existing elapsed-time calculation. This is a
single Planka-side workflow gate result, not an inventory of all memberships or
a report of GitHub's separate PR gate. Human output retains legacy `free`, or
`held`, `claimed`, and `age` lines. A successful empty scope returns `free`.

The reader uses existing `GET /api/projects` board discovery, reads every
accessible board in response order, and obtains the signed-in user's identity.
It then reuses `LoopLock` selection: first claimed open card in board/card
response order whose latest parsed `Branch:` handoff has no `PR:` URL. Comments
are read only for candidate open cards claimed by this user, until one qualifies.
A newer branch-only handoff supersedes an older PR handoff under the existing
rule. Closed cards, quarantined cards (labelled `quarantine`) and claims by
other users do not hold this gate; legacy `loop-lock` keeps its original rule
and still reports a quarantined claim. There are
no GitHub requests, resource writes, or lock acquisition.

[ClaimStatus](../lib/planka/workflow/claim_status.rb) supplies validated reads to
existing `LoopLock.report`, leaving legacy behavior intact. Canonical client
board discovery validates its collection shape and numeric board IDs before
board requests. The reader validates native list types/references, numeric card
IDs, card names, duplicate card IDs, membership identities/references and ISO
timestamps, signed-in identity, and inspected comment text/timestamps. Missing
required index collections and malformed records yield sanitized `api_error`
with null data and exit 1. HTTP/network errors follow the shared canonical
contract; cleanup failure preserves both the primary failure and successful
read results. Expected timestamp parse failures are converted near consumption,
without broadly masking programming errors.

The generic invocation descriptor supports a command without a reference;
workflow naming, help, formatter, and operation remain in the workflow module.
`loop-lock` and `planka-loop-lock` retain their arguments, bare JSON, human
output, and exits indefinitely, with replacement help and no runtime warnings.
Acceptance uses the existing public subprocess/local HTTP seams for free/held,
legacy equivalence, latest handoff, closed/other-user claims, cross-board scope,
offline help, flag placement, pre-network validation, malformed records, API
failures, read boundaries, and cleanup. Endpoint evidence is existing client
operations and captured/local fixtures; no new live-version compatibility or
live-resource mutation claim is made.

## Implemented sixth slice: workflow guide

`planka workflow guide` prints built-in onboarding guidance without credentials,
a repository checkout, or network access. It accepts no positional target, scope
flag, or alias. It ignores connection and workflow environment settings, including
malformed values. Root, workflow-group, and leaf help advertise the offline guide.
Common output flags work before, within, or after the command path.

Success JSON is `{"data":{"instructions":"..."},"meta":{},"error":null}`.
Human output is the identical instructions string, with a trailing newline.
Guidance uses implemented canonical board/card descriptions, claim inspection,
branch naming, and pending criteria; it explicitly marks remaining legacy queue,
claim, comment, publishing, and recovery commands. It does not advertise planned
replacements as available. The guide stays concise (at most 500 words).

[Workflow::Guide](../lib/planka/workflow/guide.rb) owns the current instructions
and returns their data without IO, environment reads, or a client. Legacy
`Workflow::Prime` retains its original text. `prime` and `planka-prime` retain
arguments, human output, bare JSON, and exits indefinitely; their help names the
implemented replacement without runtime warnings.

The command descriptor selects `session: false` and `reference: false`.
Shared invocation parsing validates syntax first; the coordinator executes this
operation and renders through canonical output before configuration or session
creation. It does not sign in or sign out. API readers retain the default session
path. Invalid targets, unsupported flags/formats, or conflicting output flags
return `invalid_input`, null data, empty meta, and exit 2 in JSON mode, with a
safe diagnostic on stderr. No API capability or new endpoint is introduced.

Acceptance uses approved public subprocess and installed-gem seams: offline
human/JSON equivalence, flag placement, absent/valid/malformed settings, no
connection to a local listening server, input failures, help, all legacy entry
points, and unchanged legacy guide text/JSON. Existing HTTP/session tests cover
regression of API-backed commands. These checks do not claim live API compatibility.

## Implemented seventh slice: next work

`planka workflow next [--board BOARD] [--label LABEL]` migrates `next-card` without
claiming a card, changing Planka resources, or changing Git/GitHub resources.
The three connection settings are validated before authentication. `--board`
accepts a numeric board ID or same-instance `/boards/ID` URL; otherwise
`PLANKA_BOARD_ID` is required. Explicit scope overrides the environment.
Missing/invalid default board settings are `configuration_error` (exit 1);
invalid explicit scope is `invalid_input` (exit 2), before requests.
`PLANKA_BRANCH_PREFIX` does not configure selection. No positional target,
operation alias, `--limit`, `--member`, or `--name` is introduced.

Repeated `--label` values match exactly with AND before selection. At most one
distinct `feature:` or `effort:` label selects a mode; unrelated labels narrow
that mode. Repeating the same label has no additional effect. Multiple distinct
mode labels, empty labels, or conflicting board flags fail as `invalid_input`
before configuration or network access. These are the approved label-mode rules.
Unknown labels and empty matching queues succeed without a card.

The existing `NextCard.for` selector remains the operation owner. Without a mode
label, ready-for-agent tickets are selected by position, excluding claimed,
quarantined (labelled `quarantine`) and unfinished-blocked cards. A feature mode uses ticket creation order and numbers
the matching feature tickets starting at one. Specs/maps must also match all
supplied labels; blocker lookup retains the original board even when the blocker
does not match filters. An effort mode returns wayfinder:map cards and takeable
frontier cards by position. It performs no handoff or GitHub lookup.

Human output is the existing pick, waiting, or frontier report. JSON contains
that report's existing projection in `data`, with `meta: {}` and `error: null`:

- Pick: `card`, `specs`, `number` (null for priority), `blockers`, and `parent`.
  Card references have `id`, `name`, `url`. Each blocker has `card`, `branch`,
  `pullRequest`, and `pullRequestState` (nullable).
- Waiting: `card: null` and `waiting`, whose card references add `claimed`,
  `quarantined` and `blockedBy` card references. Empty waiting succeeds with an empty array.
- Effort: `card` (first frontier card or null), `maps`, and `frontier` references.
  Empty frontier succeeds, retaining any matching maps.

This is workflow selection over the endpoint's included board records, not a
complete paginated resource collection. It introduces no `meta.complete`.
[NextSelection](../lib/planka/workflow/next_selection.rb) reads the scoped board,
then uses a filtered selection view over its validated workflow interpretation.
[QueueSnapshot](../lib/planka/workflow/queue_snapshot.rb) rejects malformed/missing
required collections, duplicate IDs, invalid names/positions/timestamps, unresolved
list/label/task-list/membership/linked-card references, and invalid completion
flags. It does not guess eligibility from malformed data. Linked blockers must
be resolvable in the scoped board; no cross-board hydration is added.

Selected priority/feature blockers read comments for latest parsed `Branch:`
handoffs. [HandoffComments](../lib/planka/workflow/handoff_comments.rb) validates
comment text/timestamps before interpretation. A newer branch-only handoff
supersedes an older PR handoff. No handoff or multiple unmerged blockers yield
an `AMBIGUOUS` parent under the existing rules. Recorded PR URLs invoke
`gh pr view URL --json state,headRefName`, requiring the executable and appropriate
GitHub authentication (including private repositories).
[PullRequestLookup](../lib/planka/workflow/pull_request_lookup.rb) suppresses raw
tool diagnostics. Failed lookups preserve unknown PR state and the recorded
branch, never assume a merge; missing `gh` yields `configuration_error` (exit 1).
Successful results require an OPEN/CLOSED/MERGED state and nonempty branch string;
malformed JSON or fields yield sanitized `api_error` (exit 1). GitHub MERGED
blockers contribute to parent main; other states retain their stacking branch.

Planka HTTP/network/input errors follow the shared canonical contract, with null
data on failure. Sign-out failure preserves successful reports and primary
failures. Credentials and raw upstream/tool bodies stay out of output. Root,
workflow, and leaf help work offline. All legacy `next-card` and direct executable
arguments, human text, bare JSON, exits, and lookup behavior remain unchanged
indefinitely; help names the replacement without runtime warnings. One deliberate
exception: legacy `next-card` shares the quarantine rule, so it never selects a
card labelled `quarantine` and its waiting JSON adds a `quarantined` boolean.

Shared invocation parsing accepts descriptor-owned flags only on applicable
commands. Pre-session options resolve board scope and labels. The workflow CLI
owns mode validation, help, human formatting, and JSON projection; the shared
output module continues to own the canonical envelope and status. No workflow
names enter shared parsing. Existing commands keep their default result rendering.

Acceptance uses approved CLI subprocess, local HTTP fake, and installed-gem seams
for scope/configuration, priority/creation/frontier order, AND filtering, empty and
waiting reports, legacy equivalence, blocker handoffs, deterministic fake-gh
results/failures, malformed records, offline help, request boundaries, errors,
and cleanup. Endpoint evidence remains the existing board/comment read paths and
captured/local fixtures. No live Planka or GitHub compatibility or mutation is
claimed; no new Planka endpoint is introduced.

## Implemented eighth slice: claim a card

`planka workflow claim CARD` implements [issue #24](https://github.com/marshally/planka-cli/issues/24).
The [README claim section](../README.md#canonical-claim) owns its human output,
data/meta/error schema, stable categories, and recovery instructions. It resolves
explicit card scope and the board's unique conventional in-progress list before
resource writes. It preserves membership-then-move intent, avoids duplicate
membership, and skips moves/repositioning when already in progress. Other users'
memberships remain; no exclusivity or transaction is asserted.

[Workflow::Claim::Card](../lib/planka/workflow/claim/card.rb) coordinates the claim.
[Claim::Scope](../lib/planka/workflow/claim/scope.rb) owns scoped reads and response
validation; [MutationProgress](../lib/planka/workflow/mutation_progress.rb) owns
common confirmation and failure accounting, while [Claim::Progress](../lib/planka/workflow/claim/progress.rb)
owns claim effects, result projection, and recovery state. Both write steps
confirm only after response validation. The legacy [Claim](../lib/planka/workflow/claim.rb)
adapter remains unchanged. Core [mutation outcomes](../lib/planka/mutation.rb)
carry result data/effects without depending on workflow or CLI code. Shared CLI
Output renders them and classifies failures. Required configuration/reference
checks remain before sessions; cleanup preserves success and primary failure.

Each resource write is sent without retry after a potentially applied failure.
A confirmed membership followed by failed/unknown move retains its membership ID
and known card snapshot. An uncertain step is null; the snapshot is the last
validated observation, not a claim about current server state. Caller readback
can confirm membership and placement before a new invocation completes the claim.
Pre-write/auth/configuration failures do not report a resource effect.

### Claim API evidence and verification limits

Official Community source inspected at v2.0.0 and v2.2.1:

- Membership creation: `POST /api/cards/:cardId/card-memberships`, `{userId}`,
  returning `item` with membership ID/card/user. Requires board-editor access and
  a target board member; an existing membership is rejected natively.
  [v2.0.0](https://github.com/plankanban/planka/blob/v2.0.0/server/api/controllers/card-memberships/create.js),
  [v2.2.1](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/card-memberships/create.js).
- Move: `PATCH /api/cards/:id`, `{listId, position}`, returning the card in `item`.
  Editor access is required for these fields; the target list is scoped to the
  board. The native helper computes placement/repositions and applies native
  list effects. The CLI sends no additional cleanup writes.
  [v2.0.0 controller](https://github.com/plankanban/planka/blob/v2.0.0/server/api/controllers/cards/update.js),
  [v2.2.1 controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/update.js),
  [v2.0.0 helper](https://github.com/plankanban/planka/blob/v2.0.0/server/api/helpers/cards/update-one.js),
  [v2.2.1 helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/update-one.js).
- Membership creation can natively subscribe the assigned user; preserve this
  behavior rather than adding a client subscription write.
  [v2.0.0 helper](https://github.com/plankanban/planka/blob/v2.0.0/server/api/helpers/card-memberships/create-one.js),
  [v2.2.1 helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/card-memberships/create-one.js).

These direct mutations are not collections. Read scope uses the existing card,
signed-in-user, and included board endpoints; no directory pagination or filter
endpoint is inferred. Local subprocess/HTTP fixtures verify exact effects,
no-ops, malformed data, partial/unknown outcomes and caller readback, input/config
checks, cleanup, and legacy behavior. This is source and fixture evidence, not
live acceptance or a blanket claim for all editions/releases above the floor.

## Implemented ninth slice: card members

Issue [#21](https://github.com/marshally/planka-cli/issues/21) implements card-scoped
`get members`, `get member USER`, `add member USER`, and `remove member USER`.
Singular/plural aliases share behavior. The [README contract](../README.md#canonical-card-members)
owns usage, precise human/JSON fields, ordering, filters, scopes, and recovery.
Board-member operations remain separate and planned. This also covers the
consumer request [#33](https://github.com/marshally/planka-cli/issues/33).

Core `Cards::Members` owns membership operations and validated observations;
`CLI::Resources::Cards::Members` owns command definitions, pre-session inputs, and human text.
Files mirror those namespaces: `planka/cards/members.rb` and
`planka/cli/resources/cards/members.rb`. Shared parsing and presentation remain
under `CLI`; resource-specific command modules live under `CLI::Resources`,
then their explicit parent resource. Earlier internal CardMembers constants and
loader paths are removed without aliases. Public CLI names remain `member`/`members`.

The same resource hierarchy owns card/board descriptions and their formatters:
`CLI::Resources::Cards` and `CLI::Resources::Boards`. Core detailed readers live
at `Cards::Detail` and `Boards::Snapshot`; `Card` and `Board` models remain at
the root. `Resources` combines these command modules and the members module,
retaining help ordering. Legacy show/snapshot executables call the same
resource-owned formatters; their arguments, output, and exits are unchanged.
Old CardDetail/Snapshot constants, loader paths, and shared CLI formatter methods
are removed without aliases. Labels, Lists, and TaskLists retain their existing
resource-specific owners; further canonical command modules appear when their
commands are implemented, without empty modules for planned resources.
The parser supports catalog-declared optional references and scoped names while
preserving numeric/URL-only contracts for existing commands. Shared collection
results carry data and completeness; collection failures preserve known results
and their original failure category. Shared output renders these and existing
mutation outcomes without depending on membership conventions.

### Card-member API evidence

Inspected official Community source at these exact refs:

| Release | Commit |
| --- | --- |
| v2.0.0 | `bda32e02471fcd698e05e76176bf5dadc7b9d742` |
| 2.1.1 | `a8dcd7cef3ee8d19ad05b8c734ac43f3103489e8` |
| v2.2.1 | `266246e242430d921c32badecdd447514107c568` |

All three inspected versions have the same membership endpoints and board/card
hydration strategy:

- [`GET /api/cards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/show.js)
  reads all memberships with `getByCardId`. Its included users are card creators,
  so that collection alone cannot hydrate assigned users. Read access requires
  permitted administrator/project-manager or board access; forbidden resources
  can be reported as not found.
- [`GET /api/boards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js)
  supplies board memberships and their user identities. Board cards are drawn
  from native finite lists; exact card names use that scope. Explicit card reads
  supply the membership collection even when the card is absent from the board
  snapshot. No page inputs or pagination are used for these collections.
- [`CardMembership query methods`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/CardMembership.js)
  select all memberships for the card, ordered by ID, without a limit. This is
  the completeness evidence; client-side name filters precede result limits.
- [`POST /api/cards/:cardId/card-memberships`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/card-memberships/create.js)
  takes `userId`, requires a board editor and a target board member, returns
  `item` as a membership, and reports an existing assignment as conflict.
- [`DELETE /api/cards/:cardId/card-memberships/userId:USER_ID`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/card-memberships/delete.js)
  requires board editor permission and returns the deleted membership under
  `item`. It addresses the account/card pair, not the relationship ID.
- Native [create](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/card-memberships/create-one.js)
  and [delete](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/card-memberships/delete-one.js)
  helpers maintain non-permanent card subscriptions and activity/webhooks; they
  do not move the card, delete the user, or remove unrelated memberships. The CLI
  issues no extra writes to emulate these effects.

For the earlier releases, the same files were inspected at
[v2.0.0](https://github.com/plankanban/planka/tree/v2.0.0/server/api/controllers/card-memberships)
and [2.1.1](https://github.com/plankanban/planka/tree/2.1.1/server/api/controllers/card-memberships),
including card/board readers and query methods. This is pinned source evidence,
not live acceptance, every later version, or another edition's compatibility.
Collections are separate observations, not a consistent snapshot under concurrent
membership or board changes. Concurrent add/remove conflicts preserve native errors;
read back before retrying.

Context7 was unavailable. Inspected the installed locked `net-http` 0.9.1 source
(`lib/net/http.rb`, `max_retries=` and `transport_request`) instead: its default
one retry includes DELETE. The client now disables it for every request and
performs no retries of its own (see the card slice). Development checks use Bundler 4.0.14 with the unchanged lockfile;
supported dependency/Ruby ranges still come from the gemspec and CI.

Public subprocess/local HTTP tests cover reads, exact target writes, no-ops,
names/URLs/scopes, filters/limits/completeness, malformed inputs and responses,
uncertain writes/readback, failure categories, cleanup, and offline help. Package
checks exercise installed commands outside the checkout. No live writes were
authorized or performed; subscription/activity effects are source evidence only.

## Implemented tenth slice: cards

Issue [#17](https://github.com/marshally/planka-cli/issues/17) implements `get cards`
(`--board` or `--list`, exact `--name`, repeated AND `--label`/`--member`,
`--limit`), `get card CARD`, `create card`, `update card`, `move card`, and
`delete card`. Singular/plural aliases share behavior. The
[README contract](../README.md#canonical-cards) owns usage, fields, ordering,
filters, scopes, clearing semantics, and recovery. Legacy `snapshot`,
`update-card`, and `move-card` keep their arguments, output, JSON, and exits;
their help now names the implemented replacements. `describe card/board` and
`show` are unchanged.

Card-scoped relationships stay under `Cards::*`; native cards live under `Boards`:

- `Boards::CardRecord` owns card field rules: input text/position limits, the
  validated public projection, write confirmation, and recovery references.
- `Boards::CardScope` resolves the card, board, lists, and a `Destination`
  (board, list, finiteness, append position, default card type). `Destination`
  owns the position rule: append unless positioned, none for archive/trash.
- `Boards::Cards < Resource` exposes `all`, `find`, `create`, `update`, `move`,
  and `delete`. Its `creation_type` hook selects an explicit native type or the
  verified `default_card_type`, independently of the destination's placement rule.
  `move` delegates to `Boards::CardMove` and retains the card's existing type.
- `Boards::CardMove < Resource` is scoped to its destination list. Its
  `read_record` reads the card and then its destination on the card's own board,
  so `updated_data` stays a pure projection, as the hook contract requires.

`CLI::Resources::Cards` owns command definitions, required-input checks, and human
text. Shared `CLI::CardInput` owns canonical card value checks and returns complete
pre-session inputs for collections, individual cards, card parents, creation,
updates, and moves. Scope resolution, filter defaults/conversion, fields,
description files/stdin, and positions stay behind that interface. Resource and workflow catalogs can use it without
depending on the card command catalog; legacy input adapters remain separate.

The shared catalog changed in three ways. Preparation callbacks receive the
already-resolved positional `reference:`, so scope policy can apply the default
board to names but not IDs; existing callbacks accept and ignore it. Group help is
assembled from each module's verb-keyed `GROUP_HELP`, adding `create`, `move`,
and `delete` groups. `Resource#create` takes validated attributes and observes a
creation scope, and create/update requests receive the desired state (see the hook
table below). The parser reads canonical arguments as UTF-8 regardless of the
process locale and rejects invalid UTF-8 as local input; description files are
read as UTF-8 bytes. An installed-gem run without `LANG` exposed the earlier
locale-dependent failure.

Card collections are deliberately scoped to active and closed lists: the one
native board read returns every card in those lists, without paging, and
`meta.complete` describes that scope. Archive and trash cards are excluded, and
`--list` naming an archive or trash list is rejected as `invalid_input` rather
than reported as an empty collection. Name/label/member filters are applied
client-side with the contract's exact AND semantics before `--limit`.

### Card API evidence

Inspected official Community source at v2.0.0 (`bda32e0`), 2.1.1 (`a8dcd7c`), and
v2.2.1 (`266246e`). The card controllers, card query methods, create/update
helpers, list model and list show are byte-identical across all three; the board
model differs only by the unrelated `displayCardAges` field.

- [`GET /api/boards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js)
  returns the board `item` (including `defaultCardType`) and all lists, labels,
  board memberships, users, card labels, and card memberships, but cards only from
  [finite lists](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/is-finite.js)
  (`active`, `closed`), sorted by position then ID, without a limit.
- Archive and trash cards are served only by the paged
  [`GET /api/lists/:listId/cards`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/index.js),
  which card collections do not use.
- [`GET /api/lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/show.js)
  answers only finite lists; archive/trash IDs are `LIST_NOT_FOUND`.
- [`POST /api/lists/:listId/cards`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/create.js)
  requires `type` (`project`/`story`) and `name` (at most 1024), accepts a nonempty
  `description` (at most 1048576) and a nonnegative `position`, and requires board
  editor membership. The [create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/create-one.js)
  requires a position for finite lists, normalizes it among existing positions,
  and drops it for endless lists.
- [`PATCH /api/cards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/update.js)
  accepts nonempty `name`, nonempty-or-null `description`, `listId`, and
  `position`; the [update helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/update-one.js)
  keeps the list on the card's board, requires a position when moving into a
  finite list, nulls it for endless lists, and normalizes it.
- [`DELETE /api/cards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/delete.js)
  requires board editor membership and returns the deleted card under `item`;
  [cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/delete-related.js)
  removes subscriptions, memberships, labels, task lists/tasks, and attachments,
  and sets `linkedCardId` to null on other tasks.

Context7 was unavailable. The installed locked `net-http` 0.9.1 source shows its
automatic retry (`IDEMPOTENT_METHODS_`) covers GET, HEAD, PUT, DELETE, OPTIONS,
and TRACE. `Client#request` sets `max_retries = 0` for every request and has no
retry loop: each request is sent exactly once, reads and writes alike, across the
whole library including legacy commands. A write that fails after reaching
Planka (5xx, reset, read timeout, EOF) raises `UnknownOutcome` for read-back;
failures before it is sent and HTTP rejections remain known-unapplied. This
replaces the earlier three-attempt policy and per-call `idempotent:` flags, whose
premise of a flaky proxy was never observed; Planka runs on the caller's network.
Development
checks use Bundler 4.0.14 with the unchanged lockfile.

Public subprocess/local HTTP tests cover every command, aliases, offline help at
all levels, ID/URL/name scopes and mismatches, active/closed-only reads, filters
before limits, malformed reads with partial data, local validation before requests,
exact single writes, supplied-only updates, no-ops, rejected and unknown outcomes
without retries or invented IDs, and legacy parity. This is pinned-source and fixture
evidence, not live acceptance; no live writes were authorized or performed.

## Implemented eleventh slice: lists

Issue [#18](https://github.com/marshally/planka-cli/issues/18) implements
`get lists --board BOARD` (exact `--name`, `--limit`), `get list LIST`,
`create list`, `update list`, and `delete list`. Singular/plural aliases share
behavior. The [README contract](../README.md#canonical-lists) owns usage, fields,
ordering, scopes, clearing semantics, native effects, and recovery. Legacy
`create-list` keeps its arguments, output, JSON, and exits; its help now names the
replacement. `snapshot` and `describe board` are unchanged.

- `Boards::ListScope` owns the board read, board-ordered list validation, list
  reference resolution, and the archive/trash `LIST_NOT_FOUND` rule. It was
  extracted from `CardScope`, which now composes it; card behavior is unchanged.
- `Boards::ListRecord` owns list field rules: name (128), kanban type, color enum,
  and position input checks, the validated public projection, write
  confirmation, and recovery references.
- `Boards::Lists < Resource` exposes `all`, `find`, `create`, `update`, and
  `delete`. Update and delete refuse archive/trash lists before the write.
- `CLI::Resources::Lists` owns command definitions, local validation, and human
  text. `CLI::Resources::BoardScope` owns the shared reference board policy
  (explicit `--board` asserts the parent; names fall back to `PLANKA_BOARD_ID`;
  IDs need none), now also used by cards. `CLI::Resources::ScalarFlags` owns the
  shared single-value flag checks; `Cards.validate_scope_flags` delegates to it
  for the card family.

Shared changes: `CollectionResult.limited` owns the limit/completeness rule for
card and list collections, and `Records.text?`/`Records.position?` own Planka's
UTF-16 text-length and finite nonnegative position rules. `Client#create_list`
validates its `item` in canonical sessions; legacy calls are unchanged.

Collections and creates require an explicit `--board`, matching `get cards`,
which requires `--board` or `--list`. `PLANKA_BOARD_ID` resolves only list names.
Unlike card collections, list collections include archive and trash lists,
because the board read returns every list.

### List API evidence

Inspected official Community source at v2.0.0 (`bda32e0`), 2.1.1 (`a8dcd7c`), and
v2.2.1 (`266246e`). The list model, the list create/show/update/delete
controllers, their create/update/delete helpers, the list query methods,
`is-finite`, `is-kanban`, `get-kanban-lists-by-id`, and `insert-to-positionables`
are byte-identical across all three.

- [`GET /api/boards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js)
  includes every list on the board, of all four types, sorted by position then
  ID, without paging.
- [`GET /api/lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/show.js)
  answers only finite (`active`/`closed`) lists; archive/trash are `LIST_NOT_FOUND`.
- [`POST /api/boards/:boardId/lists`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/create.js)
  requires `type` (`active`/`closed`), a nonnegative `position`, and `name` (at most
  128), and board editor membership. The [create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/create-one.js)
  inserts the position among the board's kanban lists and may renumber them.
  The [model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/List.js)
  rejects empty names and fixes the color enum.
- [`PATCH /api/lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/update.js)
  accepts nonempty `name` (at most 128), nullable `color` from the enum, nonnegative
  `position`, `type` (`active`/`closed`), and `boardId`, which the CLI never
  sends. It refuses archive/trash lists and non-editors as `NOT_ENOUGH_RIGHTS`.
  The [query method](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/List.js)
  applies a type change in one transaction: active→closed sets the list's cards
  `isClosed` and completes tasks linked to them; closed→active reverses both.
- [`DELETE /api/lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/delete.js)
  refuses archive/trash lists and non-editors; the
  [delete helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/delete-one.js)
  moves the list's cards to the board's trash list with a null position, then
  returns the list under `item` and those cards under `included.cards`.

Context7 was not used; the evidence is the pinned upstream source above.
Development checks use Bundler 4.0.14 with the unchanged lockfile.

Public subprocess/local HTTP tests cover every command, aliases, offline help at
all levels, ID/URL/name scopes and mismatches, all native list types in board
order, name filters before limits, malformed reads, local validation before
requests, exact single writes, supplied-only updates with explicit null color,
no-ops, archive/trash refusals, type-change effects and card-to-trash deletion
as modelled by the fake, rejected and unknown outcomes without retries or
invented IDs, and legacy `create-list` parity. This is pinned-source and fixture
evidence, not live acceptance; no live writes were authorized or performed.

## Implemented twelfth slice: resume a ticket

`planka workflow resume ticket CARD --criteria-file FILE|-` implements
[issue #25](https://github.com/marshally/planka-cli/issues/25), the canonical
replacement for legacy `create-ticket --card`. The
[README section](../README.md#canonical-resume-ticket) owns its human output,
data/meta/error schema, error codes, and recovery instructions.

It is the first three-word canonical path. `CLI::Catalog` resolves the longest
declared command path (three words, then two), so a two-word command whose
reference is the third word is unaffected. Catalogs key groups by path arrays,
such as `["workflow"]` and `["workflow", "resume"]`, and nested group help is
offline at every level. The parser derives argument counts from the resolved
path length. Later three-word workflows (`workflow create spec|ticket`,
`workflow add|remove blocker`) attach through the same catalog role.

`Workflow::CLI::TicketInput.resume` reads `--criteria-file` (or stdin) before
authentication and requires a nonempty JSON array of distinct, nonblank strings
of at most 1024 UTF-16 code units. Missing connection settings are reported
first (exit 1); file, JSON and shape failures exit 2. The command's `--criteria-file` flag
uses the shared scalar-flag checks.

[Resume::Ticket](../lib/planka/workflow/resume/ticket.rb) coordinates the fill
with the same structure as `Claim::Card`. [Resume::Scope](../lib/planka/workflow/resume/scope.rb)
reads the card once, validates its task lists and tasks, rejects two or more
`Acceptance criteria` lists as `ambiguous_criteria_list` before writes, and
validates each write response. [MutationProgress](../lib/planka/workflow/mutation_progress.rb)
owns common confirmation and failure accounting; [Resume::Progress](../lib/planka/workflow/resume/progress.rb)
owns resume effects, result projection, and `resume-ticket`
recovery. Each write is confirmed only after its response validates; an
uncertain step is recorded with null identity. Legacy `Publishing#resume_ticket`
and the `create-ticket` adapter keep their behavior and JSON shape. Their help
names only the implemented resume replacement. Canonical sessions now reject a
missing `item` from task-list and task creates as an invalid response instead
of a `KeyError`; legacy sessions are unchanged.

### Resume API evidence

Inspected official Community source at v2.0.0 (`bda32e0`) and v2.2.1 (`266246e`).
The task and task-list create controllers are byte-identical blobs across both
tags, and the card show controller includes the same records.

- [`GET /api/cards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/show.js)
  returns the card under `item` with all of its `taskLists` and their `tasks`
  under `included`, without paging.
- [`POST /api/cards/:cardId/task-lists`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/task-lists/create.js)
  requires a nonnegative `position` and `name` (at most 128), accepts
  `showOnFrontOfCard`, and requires board editor membership. The CLI sends
  `name: "Acceptance criteria"`, one gap after the card's last task list, and
  `showOnFrontOfCard: true`, as legacy creation does.
- [`POST /api/task-lists/:taskListId/tasks`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/tasks/create.js)
  requires a nonnegative `position` and either `linkedCardId` or a nonempty
  `name` of at most 1024 characters; it requires board editor membership. The
  CLI sends only `name` and one gap after the list's last task.

No endpoint checks for duplicate task names; the CLI's exact-text match is a
client convention. Context7 was not used; the evidence is the pinned upstream
source above. Development checks use Bundler 4.0.14 with the unchanged lockfile.

Public subprocess/local HTTP tests cover nested help, aliases, local input and
configuration precedence before requests, exact write bodies, list creation,
reuse with preserved completion/order, no-ops, duplicate-list refusal, malformed
reads and write responses, rejected and unknown outcomes without retries or
invented IDs, rerun recovery without duplicates or card creation, stdin input,
cleanup failure, the offline guide, and legacy `create-ticket` parity. This is
pinned-source and fixture evidence, not live acceptance; no live writes were
authorized or performed.

## Implemented thirteenth slice: task lists

Issue [#19](https://github.com/marshally/planka-cli/issues/19) implements
`get task-lists --card CARD` (exact `--name`, `--limit`), `get task-list TASK_LIST`,
`create task-list`, `update task-list` (name only), and `delete task-list`.
Singular/plural aliases share behavior. The [README contract](../README.md#canonical-task-lists)
owns usage, fields, ordering, scopes, native defaults and effects, and recovery.
Legacy `create-task-list` and `rename-task-list` keep their arguments, output,
JSON, and exits; their help now names the replacements. `describe card`,
`workflow pending-criteria`, and `workflow resume ticket` are unchanged.

Task lists are card-owned, so they live under `Cards`, parallel to board lists:

- `Cards::TaskListScope` owns the card read, card-ordered task-list validation,
  and task-list reference resolution. An ID alone finds its card through the
  task-list show endpoint; `--card` asserts the parent, and `--board` asserts the
  card's board through `Cards::Scope`.
- `Cards::TaskListRecord` owns task-list field rules: name (128) and position
  input checks, the validated public projection, write confirmation, and
  recovery references.
- `Cards::TaskLists < Resource` exposes `all`, `find`, `create`, `update`
  (name only), and `delete`.
- `CLI::Resources::Cards::TaskLists` owns command definitions, local validation,
  and human text, reusing `Cards.prepare_scope` for card scope and `BoardScope`
  for an ID's asserted board.

Shared change: `Command#collection` is the URL path segment of same-instance
references, and nil now means the resource has no URL. Planka has no task-list
page, so the parser accepts only IDs and names; an empty segment previously let
`<base>//ID` resolve. `Client#task_list` and `#delete_task_list` are added;
`#update_task_list` validates its `item` in canonical sessions, and legacy
`rename-task-list` is unchanged.

Canonical create sends only `name` and `position`, so native defaults apply
(`showOnFrontOfCard` true, `hideCompletedTasks` false). Legacy `create-task-list`
still sends `showOnFrontOfCard: false` and `workflow resume ticket` still sends
true; neither changes. The built-in workflow guide, which is also the legacy
`prime` output, still names the legacy task-list commands alongside the other
legacy publishing commands; reconciling it belongs to sequence step 5.

### Task-list API evidence

Inspected official Community source at v2.0.0 (`bda32e0`), 2.1.1 (`a8dcd7c`), and
v2.2.1 (`266246e`). The task-list model, the create/show/update/delete
controllers, the create/update/delete/delete-related and path helpers, and the
task-list query methods are byte-identical across all three. The routes
`POST /api/cards/:cardId/task-lists` and `GET`/`PATCH`/`DELETE /api/task-lists/:id`
exist in each.

- [`GET /api/cards/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/show.js)
  includes all of the card's `taskLists` via
  [`getByCardId`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/TaskList.js),
  sorted by position then ID, without a limit or paging. This is the collection
  completeness evidence; name filters are applied client-side before limits.
- [`GET /api/task-lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/task-lists/show.js)
  returns the task list under `item` (with `cardId`) and its tasks under
  `included.tasks`. Non-members who are not project managers or permitted admins
  receive `TASK_LIST_NOT_FOUND`, as for a missing ID.
- [`POST /api/cards/:cardId/task-lists`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/task-lists/create.js)
  requires a nonnegative `position` and `name` (at most 128), accepts
  `showOnFrontOfCard` and `hideCompletedTasks`, requires board editor membership,
  and returns `item`. The [create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/task-lists/create-one.js)
  inserts the position among the card's task lists and may renumber them. The
  [model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/TaskList.js)
  requires `name`, defaults `showOnFrontOfCard` to true and `hideCompletedTasks`
  to false. No endpoint checks for duplicate names.
- [`PATCH /api/task-lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/task-lists/update.js)
  accepts a nonempty `name` (at most 128), `position`, `showOnFrontOfCard`, and
  `hideCompletedTasks`, and requires board editor membership. It has no card
  input, so a task list cannot change card. The CLI sends only `name`.
- [`DELETE /api/task-lists/:id`](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/task-lists/delete.js)
  requires board editor membership and returns the deleted task list under
  `item`; [cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/task-lists/delete-related.js)
  deletes its tasks. The card and its other task lists are untouched.

Context7 was not used; the evidence is the pinned upstream
source above. Development checks use Bundler 4.0.14 with the unchanged lockfile.

Public subprocess/local HTTP tests cover every command, aliases, offline help at
all levels, ID/name scopes, rejected URL forms, `--card`/`--board` mismatches,
card order, name filters before limits, malformed and duplicate records, local
validation before requests, exact single writes with native-default create
bodies, name-only updates that keep tasks, no-ops, task cleanup on deletion as
modelled by the fake, rejected and unknown outcomes without retries or invented
IDs, and legacy `create-task-list`/`rename-task-list` parity. An installed-gem
run in an isolated `GEM_HOME`, outside the checkout and without `LANG`, exercised
each command, a rejected URL reference, leaf help, and both legacy executables.
This is pinned-source and fixture evidence, not live acceptance; no live writes
were authorized or performed.

## Implemented label resource operations

Issue [#16](https://github.com/marshally/planka-cli/issues/16) adds native
`get labels`, `get label`, `create label`, `update label`, and `delete label`.
The existing card-scoped `add label`/`remove label` complete the resource slice.
The [README contract](../README.md#canonical-labels) owns command syntax, schemas,
human output, input rules, ordering, completeness, and recovery.

`Boards::Labels` implements the supported Resource hooks and uses `collect` for
partial collection results and the Resource/Write lifecycle for mutations.
`Boards::LabelRecord` owns field validation, projection, confirmation, and
readback references; `CLI::Resources::Labels` owns CLI scope/default preparation,
flags, help, and presentation. `Cards::Labels` retains card-label relationships;
legacy `Planka::Labels` retains exact-name reuse and its original projections.
The general library still loads without CLI/workflow code or environment access.

Collection reads and creates require explicit `--board`, matching other current
board-resource commands. Individual operations require `--board` or
`PLANKA_BOARD_ID` even for numeric IDs. The CLI does not issue an unsupported
label GET or search other boards. Create always makes a new label. Known label
IDs from malformed create responses are retained for readback, while an ID
already present in the pre-write snapshot is never accepted as a new creation.
Positions may be server-normalized. No resource writes occur during reads;
there are no client assignment sweeps or retries after unknown mutations.

### Label API evidence

Inspected official **Community v2.2.1** source for this implementation:

| Contract | Official source |
| --- | --- |
| POST `/api/boards/:boardId/labels`, PATCH/DELETE `/api/labels/:id`; no individual label GET route | [Routes](https://github.com/plankanban/planka/blob/v2.2.1/server/config/routes.js) |
| Board visibility checks and full `included.labels` from `Label.qm.getByBoardId`; no label paging parameters or query limit | [Board show](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js), [label query methods](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Label.js) |
| Numeric-string ID and board ID, nullable name/timestamps, numeric position, 42 allowed colors | [Label model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/Label.js) |
| Create accepts nonnegative position, nullable/nonempty name up to 128 UTF-16 units, required color; returns `{item: label}`; board editor required | [Create controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/labels/create.js) |
| Update accepts only supplied name/color/position; returns `{item: label}`; board editor required | [Update controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/labels/update.js) |
| Create/update normalize positions and may renumber neighbors on the server | [Create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/labels/create-one.js), [update helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/labels/update-one.js) |
| Delete requires board editor membership and returns the deleted label; cleanup removes CardLabel assignments, preserving cards | [Delete controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/labels/delete.js), [cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/labels/delete-related.js) |
| Card-label mutations require same-board identities and board editor access; return relationship records | [Add controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/card-labels/create.js), [remove controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/card-labels/delete.js) |

The CLI requires a nonblank name for create/update, does not expose clearing,
and still reads native unnamed labels. `/labels/ID` is a supported CLI reference
form; it is not a native browser route. Legacy `labels` continues reading the
complete board snapshot rather than a narrower labels endpoint.

Context7 was unavailable. The locked bundle is Bundler 4.0.14, net-http 0.9.1,
and minitest 6.0.6; installed source was inspected. `Net::HTTP#transport_request`
can retry DELETE by default; Client already sets `max_retries = 0`. Dependency
versions and Gemfile.lock are unchanged. The public CLI/local HTTP tests cover
all label verbs, no-ops, partial malformed reads, exact writes, uncertain results,
cleanup, and legacy flat/direct parity. Installed-gem verification exercises
commands outside the checkout with the package path checked in each subprocess.
These checks and pinned source evidence do not prove live write acceptance or
compatibility across all editions/releases. No live writes were performed.

## Implemented comment resource operations

Issue [#20](https://github.com/marshally/planka-cli/issues/20) adds card-scoped
`get comments`, `get comment`, `create comment`, `update comment`, and
`delete comment`. The [README](../README.md#canonical-comments) owns usage,
fields, exact text/clearing rules, human output, permissions, and recovery;
the [style guide](../STYLEGUIDE.md#comments) marks the implemented grammar.

`Cards::Comments < Resource` owns comment reads and the native create/update/delete
hooks. `Cards::CommentRecord` owns input text rules, response validation,
projection, and recovery identities. Existing `Cards::Scope` resolves the card
and checks explicit board agreement. `CLI::Resources::Cards::Comments` owns
flags, local preparation, help, and human presentation. The shared Resource/Write
lifecycle handles no-ops, single writes, rejected/unknown outcomes, and cleanup
presentation through the existing CLI. No workflow interpretation enters core.

`Client#comments_page` uses the native `beforeId` cursor independently of
`Client#comments`. The latter and legacy `Client#comment` keep their old shapes
and behavior for `describe`, `show`, handoff parsing, claim inspection, and flat
`comment`/`planka-comment`. Canonical reads validate each record's scope and
strictly decreasing numeric ID before exposing it; a repeated cursor, wrong card,
malformed record or page fails without looping. Collections fetch through the
last page before limiting; individual lookups stop at the requested record.

### Comment API evidence

Inspected official Community tags `v2.0.0`, `2.1.1`, and `v2.2.1`. The four comment
controllers, query-method implementation, three write helpers, and comment model
are byte-identical across these tags. Links below pin the inspected v2.2.1 source;
this does not establish every later release or edition's behavior.

- [Routes](https://github.com/plankanban/planka/blob/v2.2.1/server/config/routes.js)
  provide collection GET, POST, PATCH and DELETE, with no individual comment GET.
  [Client paths](https://github.com/plankanban/planka/blob/v2.2.1/client/src/constants/Paths.js)
  have card/board/project routes and no comment page. COMMENT therefore accepts
  numeric IDs only, and explicit card scope is required for every command.
- [Index controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/comments/index.js)
  checks card access and returns `items` plus related users. The CLI does not
  expose those users. [Query methods](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Comment.js)
  limit pages to 50, sort `id DESC`, and constrain `id < beforeId`. A short page
  proves exhaustion in a stable dataset; a full page requires another request.
  Pagination is not transactional across requests.
- [Create controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/comments/create.js)
  accepts required text with a 1,048,576-character JavaScript limit and returns
  `item`. It requires board membership with editor or viewer `canComment` rights.
  The [helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/comments/create-one.js)
  preserves text and handles notifications/events; query methods maintain the
  card's comment count and timestamp within the native transaction.
- [Update controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/comments/update.js)
  accepts nonempty text up to the same limit, returns `item`, and requires the
  author plus board editor/viewer comment rights. Native rejection can be 404
  for a non-author or missing membership, or 403 for insufficient comment rights.
  The [helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/comments/update-one.js)
  sends the supplied values to the native update; the CLI sends only text.
- [Delete controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/comments/delete.js)
  permits a project manager, or the author with board editor/viewer comment rights,
  and returns the deleted `item`. The [helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/comments/delete-one.js)
  deletes that comment and emits events; query methods decrement the card's comment
  count and update its timestamp. No linked card or sibling comment is deleted.
- [Comment model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/Comment.js)
  defines card identity, nullable author, and text; timestamp fields are nullable.
  The CLI whitelists these fields, rejects blank new text without trimming it,
  and exposes no clear-text operation.

### Comment verification boundary

Standing approved seams are CLI subprocesses against local HTTP fixtures, legacy
flat/direct executable parity, and isolated installed-gem checks. Acceptance
covers all commands, native page boundaries/order, limits, malformed/partial
reads, no resource writes on reads, exact text and target effects, update no-ops,
pre-request rejection, parent disagreement, unknown-write readback, known returned
IDs, rejected writes, and cleanup preserving the primary result. The comment HTTP
fixture is isolated from older handoff fixtures so their synthetic IDs/order do
not silently change. The full suite protects workflow and legacy contracts.

Development uses the copied existing untracked lockfile: Bundler 4.0.14,
net-http 0.9.1, minitest 6.0.6, and RuboCop 1.91.0. No dependency upgrades were
made. Context7 was unavailable; installed locked net-http source was inspected
for request/retry behavior (`Net::HTTP#max_retries=`, already set to zero by
Client), and URI 1.1.1 supplies query encoding. This is installed-source evidence,
not current-version documentation. Source inspection, local fixtures, and package
checks do not prove live compatibility. No live Planka writes were authorized or
performed; report remote CI separately in the implementation PR.

## Implemented board resource operations

Issue #22 delivers project-scoped `get boards`, `get board`, `create board`,
`update board`, and `delete board`, with singular/plural aliases and offline
help. [README](../README.md#canonical-boards) owns the detailed schemas, human
output, and recovery contract; [STYLEGUIDE](../STYLEGUIDE.md#basic-board-creation-and-updates)
records the settled behavior. `describe board` and legacy `snapshot` remain unchanged.

`Projects::Boards < Resource` owns project collection reads, board resolution,
and native CRUD hooks. `Projects::BoardRecord` owns field validation, concise
projection, response confirmation, and recovery references. CLI preparation
resolves IDs/same-instance URLs and explicit project scope before authentication;
board names require that scope, while project names are unsupported. `Resource`
owns mutation ordering/no-op detection, `Write` owns certainty, and `collect`
preserves validated, sorted, filtered partial reads. Core loading stays independent
of workflow/CLI. Collection and creation scope is explicit; no environment board
or cross-project fallback is consulted.

### Board API evidence

Inspected official **Planka Community v2.2.1** source for these contracts:

| Contract | Official pinned evidence |
| --- | --- |
| `GET /api/projects/:id` returns project `item` and all caller-visible `included.boards` without paging. Managers see the project's boards; members can see their boards; admins have additional visibility for projects without an owner manager. | [Project show](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/show.js), [board queries](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Board.js) |
| `GET /api/boards/:id` returns a board `item` after native access checks. Only the concise board is projected here; snapshot contents are not changed. | [Board show](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js), [board model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/Board.js) |
| POST `/api/projects/:projectId/boards` requires project-manager access and name/position, returns `item`; name limit 128, position >= 0. Native creation adds creator editor membership and archive/trash lists transactionally. | [Create controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/create.js), [create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/boards/create-one.js), [query methods](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Board.js) |
| Default append is last position + 65536. Native insertion/update may normalize positions and reposition neighbors; returned positions are authoritative. The CLI sorts position/ID independently, since member-only project reads can use ID order. | [Position selectors](https://github.com/plankanban/planka/blob/v2.2.1/client/src/selectors/positioning.js), [gap](https://github.com/plankanban/planka/blob/v2.2.1/client/src/constants/Config.js), [native normalization](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/utils/insert-to-positionables.js) |
| PATCH `/api/boards/:id` accepts name/position for managers and returns `item`; other native display/subscription fields stay outside this CLI slice. | [Update controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/update.js), [update helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/boards/update-one.js) |
| DELETE `/api/boards/:id` requires manager access and returns the deleted board `item`. Native cleanup removes memberships, labels, lists/cards, and related data. | [Delete controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/delete.js), [board cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/boards/delete-related.js), [list cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/delete-related.js) |

Collection completeness is limited to native visibility at read time. Append is
computed before the write and is not atomic with concurrent board changes.
Native side effects and permissions are source-backed, not inferred from fake
responses. No live board mutations were authorized or performed; fixture/package
checks do not establish compatibility for other releases or editions.

Verification uses the agreed public CLI subprocess/local HTTP seams in
`board_resources_cli_test.rb`, including aliases, pre-request validation,
read-only effects, supplied-field/no-op updates, target-only deletion, partial
collections, malformed write confirmation, readback identity, uncertain writes,
cleanup, and legacy/direct parity. Context7 was unavailable; dependency behavior
was checked against installed locked Minitest 6.0.6 and net-http 0.9.1 source,
using Bundler 4.0.14. No dependency upgrade is part of this slice.

## Implemented project resource operations

Issue [#23](https://github.com/marshally/planka-cli/issues/23) implements
`get projects`, `get project PROJECT`, `create project --name NAME`,
`update project PROJECT`, and `delete project PROJECT`, with aliases and offline
root/group/leaf help. [The README contract](../README.md#canonical-projects)
records inputs, output schemas, permissions, order/completeness, and recovery.

`Planka::Projects` owns instance-scoped reads/resolution and supplies the existing
Resource create/update/delete hooks. The Projects namespace is now a Resource
subclass, preserving nested `Projects::Boards` and `Projects::BoardRecord`
interfaces from #22. `Projects::Record` owns field validation,
projection, native limits, confirmation, and recovery references. Client owns
native endpoints; `CLI::Resources::Projects` owns flags, pre-session input-file
reading, command preparation, help, and formatting. No workflow dependency or
new persistence/session layer is introduced. Explicit project URLs are resolved
by the shared CLI Instance; library callers supply numeric IDs or exact names.

Collections preserve response order and validate even records beyond the output
limit; malformed/duplicate records preserve validated matching results with
`complete: false`. Name resolution must inspect the complete accessible collection;
an incomplete lookup returns its original error without pretending its partial
collection identifies one project. Individual reads verify the returned ID.
Creation observes an unknown project with null fields, then issues one native
POST. Updates send supplied differences and skip identical values. Deletion sends
only the target DELETE. Shared Write classification retains known state on
rejection, uncertain fields on unknown outcomes, and a valid returned creation ID
for readback. No retry or child/manager mutation is performed.

### Project API evidence

Official **Community v2.2.1**, inspected for this implementation:

- [Index controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/index.js)
  accepts no pagination inputs. It returns managed and board-membership projects,
  plus other shared projects for administrators, in `items`; included board/user
  records are unnecessary for the concise project projection. The
  [query methods](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Project.js)
  sort each query by ID, but the controller appends the shared group separately.
  Preserve response order rather than claim a globally sorted snapshot.
- [Show controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/show.js)
  returns `item`; managers and project-board members may read, while administrators
  additionally see shared projects. Denied access can return 404. The
  [client paths](https://github.com/plankanban/planka/blob/v2.2.1/client/src/constants/Paths.js)
  verify `/projects/:id` URLs.
- [Create controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/create.js)
  accepts required `type: private|shared`, required name (128), optional nullable
  nonempty description (1024), returning `item` plus `included.projectManagers`.
  [Policies](https://github.com/plankanban/planka/blob/v2.2.1/server/config/policies.js)
  and the [role predicate](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/users/is-admin-or-project-owner.js)
  restrict creation to administrator/projectOwner accounts. The
  [create query](https://github.com/plankanban/planka/blob/v2.2.1/server/api/hooks/query-methods/models/Project.js)
  creates the project and caller's manager relationship in one native transaction,
  setting `ownerProjectManagerId` for private projects. No persisted `type` field
  appears in the [model](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/Project.js);
  read type derives from ownership. No client manager writes are required.
- [Update controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/update.js)
  requires project-manager permission for name/description and accepts the same
  lengths with explicit nullable description. It returns `item`. CLI updates
  exclude ownership, background, hidden/favorite inputs. Length checks use the
  native JavaScript UTF-16 convention through existing `Records.text?`.
- [Delete controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/projects/delete.js)
  requires manager permission. The
  [delete helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/projects/delete-one.js)
  rejects when any board remains (422), before native cleanup/deletion. Successful
  empty-project deletion performs native
  [related cleanup](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/projects/delete-related.js),
  including managers, favorites, backgrounds, and custom-field settings.

Routes are `GET/POST /api/projects` and `GET/PATCH/DELETE /api/projects/:id` in
[official routes](https://github.com/plankanban/planka/blob/v2.2.1/server/config/routes.js).
No endpoint is inferred from a fixture. Permission decisions remain with the
server, and missing/inaccessible resources are never reinterpreted as successful
empty results or a reason to write related resources.

### Project verification boundary

Standing approved seams are CLI subprocesses against local HTTP fixtures,
installed-gem executables outside the checkout, and legacy parity. The project
fixture extends only the HTTP route boundary and preserves the shared session,
fault-injection, and legacy routes. Red/green slices cover each command, input
validation, native creation effects, no-op updates, nonempty deletion, returned
identity, malformed/partial reads, unknown writes, and cleanup precedence.

The ignored development lockfile is reused unchanged: Bundler 4.0.14,
net-http 0.9.1, Minitest 6.0.6, RuboCop 1.91.0. Context7 is unavailable in this
session; the installed locked net-http source confirms `max_retries = 0` disables
retries, and installed Minitest source verifies assertion behavior. No dependency
upgrade or new dependency API is required. This is locked-source verification,
not a claim of version-matched Context7 documentation.

Official source plus local fixture/package checks do not prove live instance
compatibility or support across all Planka 2.x versions/editions. No live project
mutations were performed. Report actual remote CI separately in the PR.

## Implemented create spec workflow

`planka workflow create spec --list LIST --name NAME` implements
[issue #26](https://github.com/marshally/planka-cli/issues/26), with the `specs`
alias, optional `--board`, `--description-file FILE|-`, and native `--position`.
The [README contract](../README.md#canonical-create-spec) records its full input,
human output, card data schema, metadata, error codes, and recovery.

`Workflow::Create::Spec` composes `Boards::Cards#create(type: "project")`;
general cards remain independent of workflow conventions. Core creation now
accepts an explicit native type while the native CLI still uses the board default.
`Workflow::CLI` owns required flags/help and uses `CLI::CardInput` for preparation.
Three-word dispatch, pre-session settings, in-memory sessions, Output, and cleanup
handling remain shared. Legacy `create-spec` and its direct executable keep
arguments, bare JSON, human output, and exits; only their help gains the implemented
replacement. The current guide is updated, without changing legacy Prime.

`CardScope#creation` observes destination and already-visible card IDs from one
board read. `CardRecord` validates text, type, finite nonnegative positions,
confirmation, and returned identities. Resource's deferred failure hooks preserve
a valid numeric returned ID absent from the observed cards even when other fields
cannot be confirmed. Write remains the certainty/failure owner. Unknown fields
stay null, with card recovery for a known ID or list recovery otherwise; neither
retries nor extra reconciliation writes are issued. Already-observed IDs cannot
confirm new creates. These protections are shared with canonical native card
creation. `ListScope` classifies API name ambiguity as operational exit 1 with
its existing `invalid_input` code, retaining candidate IDs; explicit mismatches
remain input failures.

### Create spec API evidence

Official **Community v2.2.1** source inspected for this implementation:

| Contract | Primary source |
| --- | --- |
| POST `/api/lists/:listId/cards` requires type (`project`/`story`) and name (1024), accepts nonnegative/null position and nonempty/null description (1048576), requires board editor membership, and returns `item`. | [Create controller](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/cards/create.js) |
| Finite lists require position; native insertion may renumber neighbors. Archive/trash omit it. Creation records native actions and may subscribe the creator, but adds no Acceptance criteria list or tasks. Native failures after card creation can leave an uncertain outcome. | [Create helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/cards/create-one.js), [finite helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/is-finite.js) |
| Append uses the last position plus 65536; returned positions are authoritative. | [Position selectors](https://github.com/plankanban/planka/blob/v2.2.1/client/src/selectors/positioning.js), [position gap](https://github.com/plankanban/planka/blob/v2.2.1/client/src/constants/Config.js), [normalization](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/utils/insert-to-positionables.js) |
| GET `/api/boards/:id` supplies all visible lists and finite-list cards without pagination/filter inputs; the CLI resolves exact names and calculates append itself. Scope observation is bounded by that snapshot and native access. | [Board show](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/boards/show.js) |
| GET `/api/lists/:id` finds an active/closed list's board, rejecting infinite lists with 404; archive/trash require board scope. Canonical `get cards` reconciles finite lists only, so unknown IDs in archive/trash need inspection in Planka. | [List show](https://github.com/plankanban/planka/blob/v2.2.1/server/api/controllers/lists/show.js), [finite helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/lists/is-finite.js) |

Append is a read followed by a write, not atomic with concurrent changes. Source
inspection establishes endpoint/field/access behavior, not compatibility with
every edition or later version. No live Planka acceptance or live writes were
authorized or performed.

Verification uses red-green CLI subprocess/local HTTP tests in
`workflow_create_spec_cli_test.rb`: project type on a story board, exact input,
append and supported positions, file/stdin text, aliases/offline help, duplicate
creates, strict response validation and ID preservation, lookup/input/settings/
API failures, uncertain effects without retries, readback without writes, cleanup
precedence, and legacy/direct parity. Existing card/list/loading/CLI suites protect
shared behavior. Locked Bundler 4.0.14 and repository CI/build plus an isolated
installed-gem check are the package verification boundary; fixtures and package
checks do not substitute for live API evidence. Context7 is unavailable; no new
dependency APIs or upgrades are introduced.

## Canonical CLI architecture

General design and review rules live in
[CODING_STANDARDS.md](../CODING_STANDARDS.md). This section records the current
owners and their interfaces.

The coordinator in [canonical_cli.rb](../lib/planka/canonical_cli.rb) follows
parse → validate → open session → execute → render for API commands.
Offline operations execute and render after parsing, without configuration or a
session. The executable alone exits
for canonical commands; the coordinator and output module return a status.
Legacy executables retain their existing argument/output adapters.

| Owner | Interface and responsibility |
| --- | --- |
| [CLI::Resources](../lib/planka/cli/resources.rb) | Combines resource-owned command definitions and help into the shared catalog role. |
| [CLI::Resources::Cards](../lib/planka/cli/resources/cards.rb), [CLI::Resources::Boards](../lib/planka/cli/resources/boards.rb), [CLI::Resources::Cards::Members](../lib/planka/cli/resources/cards/members.rb), [Workflow::CLI](../lib/planka/workflow/cli.rb) | Own paths, aliases, help, applicable flags, local validation, callable operations, presentation, and command-specific preparation. |
| [CLI::Catalog](../lib/planka/cli/catalog.rb) | Combine resource commands with explicitly attached catalogs and resolve the longest declared two- or three-word path or alias. Own root/group/leaf help selection; groups are keyed by path arrays. |
| [CLI::Parser](../lib/planka/cli/parser.rb) | `parse` owns mutable option parsing and local syntax validation, returning an immutable invocation. No configuration or execution. |
| [CLI::Invocation](../lib/planka/cli/invocation.rb) | Immutable snapshot of the selected definition, program, output format, reference, flags, and optional help text. No parsing, environment access, preparation, or execution. |
| [CLI::Configuration](../lib/planka/cli/configuration.rb) | `from_env` captures required connection settings and provides session arguments. Credentials are frozen and inspection is redacted. Owns a validated instance, not resource-reference resolution. |
| [CLI::Instance](../lib/planka/cli/instance.rb) | Own the validated server URL, including instance path, and `resolve` numeric IDs or same-instance resource URLs. No credentials, environment defaults, or command policy. |
| [CLI::PreparedCommand](../lib/planka/cli/prepared_command.rb) | `build` validates configuration, resolves explicit references, invokes catalog preparation, and captures executable operation arguments before authentication. Offline commands require no connection settings. `execute` accepts the session client. |
| [CLI::Output](../lib/planka/cli/output.rb), [CLI::Failure](../lib/planka/cli/failure.rb) | Render canonical envelopes, catalog-selected human/JSON presentation, safe diagnostics, and statuses. Expected failures can carry known data/metadata. |
| [Client](../lib/planka/client.rb) | Own HTTP/session lifecycle. Accept explicit connection settings; canonical sessions opt into response-document and token validation. |
| [Boards::Lists](../lib/planka/boards/lists.rb), [Boards::ListScope](../lib/planka/boards/list_scope.rb), [Boards::ListRecord](../lib/planka/boards/list_record.rb), [CLI::Resources::Lists](../lib/planka/cli/resources/lists.rb) | Own native list reads, creation, updates, and deletion; board/list resolution shared with cards; list record rules; and their command definitions. |
| [CLI::Resources::BoardScope](../lib/planka/cli/resources/board_scope.rb) | Resolve the board scope of a card or list reference before authentication, classifying a bad default board as configuration failure. |
| [CLI::CardInput](../lib/planka/cli/card_input.rb) | Validate canonical card values and return complete operation inputs through collection/card/parent/creation/update/move methods; scope, flag conversion, fields, files/stdin, and positioning remain private. Catalogs retain command-specific required-input checks. |
| [Boards::Cards](../lib/planka/boards/cards.rb), [Boards::CardMove](../lib/planka/boards/card_move.rb), [Boards::CardScope](../lib/planka/boards/card_scope.rb), [Boards::CardRecord](../lib/planka/boards/card_record.rb), [CLI::Resources::Cards](../lib/planka/cli/resources/cards.rb) | Own native card reads, creation, updates, moves, and deletion; card scope and record rules; and their command definitions. |
| [Resource](../lib/planka/resource.rb) | Own protected create/update/delete algorithms: input preparation, current-state lookup, change detection, request execution, response validation, and result construction. Concrete resources supply operation hooks and expose supported verbs. |
| [Relationship](../lib/planka/relationship.rb) | Expose association `add`/`remove` through Resource create/delete, query inclusion, and project observed/created/deleted relationship state without inspecting resource fields. |
| [Write](../lib/planka/write.rb) | Run one resource write, returning its confirmed result or preserving unchanged/unknown data and recovery references on failure. |
| Canonical readers | Read and validate only the records their operation needs. Return resource data or existing workflow reports; catalogs select result projections. |

### Resource operation algorithms

Card-label relationships, card memberships, task completion, native cards, and
native lists inherit from `Resource`. Its protected `create(reference, **attributes)`,
`update(reference, **attributes)`, and `delete(reference)` own operation
sequencing. `Tasks` makes the inherited `update` public without replacing its
algorithm; `Boards::Cards` exposes create/update/delete with card arguments, and
`Boards::CardMove` exposes a destination-scoped update as `move`. Relationship resources keep
CRUD methods protected and expose `add`/`remove` through the `Relationship` role.
Collection reads (`all` on cards, lists, and members) fill an accumulator inside
the private `collect(limit, project:)` template, which owns the limit and the
translation of operation failures into `CollectionFailure` with the projected
records read so far; `project` applies a resource's filtering and order to
partial reads too. Reference failures propagate unchanged.
No unsupported public verbs or endpoint conventions are inferred.

Create and update first validate and translate input attributes. Create then
observes its creation scope and prepares the requested state; delete resolves
validated current state and prepares the deletion state; update resolves current
state and applies the attributes to its public data.
All three compare observed and requested data, returning `changed: false` before
any write when equal. Otherwise the selected request runs inside `Write`, and
Resource validates its response before constructing confirmed data.

The private hook contract separates stable algorithms from resource details:

| Hook | Responsibility |
| --- | --- |
| `read_record(reference)` | Validate the reference and load a fresh scoped observation. For relationships, resolve the existing target even when its association is absent. |
| `creation_attributes(**attributes)` | Validate public creation input before reads; defaults to none (relationships). |
| `read_creation_scope(reference)` | Observe where a creation happens; defaults to `read_record`. Cards observe the destination list and project a card with only its board/list known. |
| `record_data(observation)` | Project current public state; defaults to the observation itself. |
| `creation_data(observation, attributes)`, `deletion_data(observation)` | Project the requested state for the supported operation. Relationship supplies these from presence semantics. |
| `update_attributes(**attributes)` | Validate public update input before reads and translate it into changed fields. Required only for resources exposing update. |
| `create_record(observation, desired)`, `update_record(observation, desired)`, `delete_record(observation)` | Execute the corresponding request through Client and return its unvalidated record; requests derive from the desired state. Implement only the supported operations. |
| `validate_record!(record, desired, observation:)` | Validate returned identity, scope, and requested effects before success is reported. Labels use the original observation to reject reused creation IDs; other implementations ignore that keyword. |
| `confirmed_data(record, desired)` | Return confirmed public data; defaults to desired state. Members incorporate server-assigned membership identity and timestamps on creation. |
| `recovery(observation)` | Describe resource-specific readback. |
| `unconfirmed_data(observation, desired, returned)` | Project uncertain state after a failed confirmation. Defaults to marking changed fields nil; labels also retain a returned new ID. |
| `unconfirmed_recovery(observation, desired, returned)` | Supply recovery after failure; defaults to `recovery(observation)`. Labels include a newly returned ID when known. |

Public state projections are flat hashes. Desired state retains known fields
and changes requested ones. For an uncertain write, Resource retains the
observed projection and marks differing requested fields nil; confirmed response
metadata is incorporated only after validation. `Write` remains the single owner
of confirmed result/failure construction and certainty classification, preserving
the original error as cause. `Write.perform` accepts eager hashes or deferred
callables for unknown data and recovery; Resource defers these projections until
the response is available. Only Write classifies certainty and constructs failure
results. Client sends each request once. Read/input failures
occur before Write; malformed write responses require readback. Multi-step
workflow progress remains separate.

`Relationship` owns presence semantics through two resource-specific messages:
`relationship_present?(observation)` returns a Boolean, and
`relationship_data(observation, present:)` projects public state. It supplies
Resource's observed, creation, and deletion projections using those messages;
`add` invokes create and `remove` invokes delete. The mixin treats observations as
opaque and reads no host instance variables or membership/label fields.

`include?` returns false only for a known target with no relationship. Unknown
or ambiguous references and failed/malformed reads raise. Adding an existing
relationship and removing an absent one are no-ops; removal preserves both
endpoints. Shared public role tests run against members and labels using the
real client and local HTTP fixture. Resource-specific and CLI acceptance tests
retain validation, result, and uncertain-write coverage.

Commands select an `operation` callable. PreparedCommand invokes `call` with
its prepared arguments; it does not require every operation to implement `read`.
Read-only commands bind existing readers through `method(:read)`. The member,
label, and task catalogs construct scoped core resources and call `all`, `find`,
`add`, `remove`, or `update`; their Ruby interface is documented under
[Library](../README.md#library). Scope/client state belongs to the resource
instance, while each operation observes fresh server data. Member/task `.read`
dispatchers and mutation-selection flags are removed. Card labels expose instance
`add`/`remove` operations instead of the internal singleton `set` dispatcher.
Resource mutations no longer accept
an unused `base_url:` argument.

The coordinator now follows parse → prepare → open session when required →
execute → render. Help returns after parsing. Offline guide preparation captures
its operation without inspecting connection settings or opening a session.
API command preparation finishes all required settings and scope validation
before authentication. Connection settings remain frozen and private.

Command-specific preparation remains with its catalog instead of introducing a
class for each command. `Workflow::CLI.next_preparation` selects an explicit board
or the environment default, asks `Instance` to resolve it, and classifies a bad
explicit value as input failure or a bad default as configuration failure.
`Instance::InvalidReference` describes resolution failure without assigning an
exit category; preparation assigns that category at the source. There is no
catch-and-relabel of an already classified CLI failure. Branch-prefix settings
remain in `Workflow::Configuration` and are captured during branch preparation.

Catalog `prepare` callbacks receive the supplied environment, validated instance,
immutable parsed flags, and the resolved positional `reference:` (nil when the
command takes none), and return the complete operation keyword arguments.
Callbacks that do not need the reference accept and ignore it with `**`.
Without a callback, preparation supplies `base_url:` for the standard detailed
readers. Custom preparation includes `base_url:` only when its operation needs
it. Operation/client inputs are captured before the session starts. General positional references are
resolved by shared preparation; workflow scope/default policy stays in its catalog.
Declared resource aliases preserve card/cards and board/boards grammar.
Shared parsing contains no resource or workflow command names.

Parser stages are private methods for options, command resolution, flag checks,
extra arguments, required arguments, reference syntax, and invocation building.
Help skips required arguments and reference syntax, while still rejecting
unsupported flags and extra arguments. Option-parser and resource-name values
are local rather than retained as redundant parser state.

This refactor changes ownership, not command behavior. Apart from changing the
root help heading from `Administration` to `Resource commands`, keep help, command
syntax, result schemas, error messages/categories, exit codes, session cleanup,
all 21 legacy entry points, and library-loading direction unchanged. Preserve
output flags before/within/after command paths, offline help/guide, pre-request
validation, configured instance paths, explicit scope precedence, and default
scope error classification. Verify at the approved public subprocess/local HTTP
and installed-gem seams, including comparison with the merged pre-refactor source.
No new tests of private parser/configuration implementation are required.

Core card models expose general resource data; workflow adapters own agent
conventions. See the [workflow module and future gem extraction](WORKFLOW_MODULE.md)
for loading, dependency direction, compatibility, and the later packaging boundary.
Malformed response documents, tokens, and required reader records raise
`Planka::InvalidResponse` near consumption and become sanitized `api_error`
failures. Output does not disguise unexpected programming exceptions as server
failures. No commands, endpoint capabilities, credential persistence, or future
workflow gem packaging are added by this refactor.

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
3. Add new resource capabilities in independently reviewable slices:
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
Requests are never retried; change that only as an explicit, documented decision.

## Settled decisions and implementation deliverables

The resource-sized [lists issue #18](https://github.com/marshally/planka-cli/issues/18)
has a settled update-field contract. See the style guide’s
[list updates](../STYLEGUIDE.md#list-updates); it is implemented in the eleventh
slice above with pinned-source and fixture evidence. Live API acceptance remains
outstanding.

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

Task scope is settled in the style guide's [tasks section](../STYLEGUIDE.md#tasks):
include ordinary and linked-card tasks, with same-board linked-task creation and
same-card moves. The approved resource ticket is
[issue #34](https://github.com/marshally/planka-cli/issues/34), expanded from the
consumer's completion-only request. No task commands are implemented.

User reads are settled in the style guide's [users section](../STYLEGUIDE.md#users):
directory and explicit board scopes, minimal identity results, explicit username
filters, authenticated-user shorthand, and username-first ordering. Account
mutations are deferred. Track implementation in
[issue #35](https://github.com/marshally/planka-cli/issues/35); no user commands
are implemented.

Card-member vocabulary is settled in the style guide's
[card members contract](../STYLEGUIDE.md#card-members). Track the four approved
card-scoped operations in [issue #21](https://github.com/marshally/planka-cli/issues/21);
implementation and precise output fields are recorded in the ninth slice above. Board members have
a separate settled slice; project managers remain separately deferred to the end
of the plan.

Pinned Community v2.2.1 evidence distinguishes the
[CardMembership relationship](https://github.com/plankanban/planka/blob/v2.2.1/server/api/models/CardMembership.js)
from the user. The [routes](https://github.com/plankanban/planka/blob/v2.2.1/server/config/routes.js)
create via `POST /api/cards/:cardId/card-memberships` with `userId`, and delete
via `DELETE /api/cards/:cardId/card-memberships/userId::userId`, addressing the
card/user pair rather than a membership ID. Read hydration, permissions, and
compatibility across the target versions require verification during implementation;
this source evidence is not live API acceptance.

Board-member grammar is settled in the style guide's
[board members section](../STYLEGUIDE.md#board-members); keep its implementation
separate from card-member and project-manager work. Its implementation ticket is
[issue #36](https://github.com/marshally/planka-cli/issues/36). Project-manager grammar
is recorded in the
[project managers section](../STYLEGUIDE.md#project-managers), but its separate
ticket, [issue #37](https://github.com/marshally/planka-cli/issues/37), is deferred
to the end of the plan, including remaining specification.
Neither surface is implemented.

Official Community v2.2.1 [board-member removal helper](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/board-memberships/delete-one.js)
also removes that user's board/card subscriptions and card memberships and clears
task assignments in the board. These are native effects of the single target
removal, not permission for client-side cleanup writes. Verify target-version
behavior during implementation; no live API acceptance is claimed.

Basic board creation/update is implemented under the style guide's
[board contract](../STYLEGUIDE.md#basic-board-creation-and-updates): project/name
creation with optional position and append default, and name/position updates
within the existing project. Implemented for
[issue #22](https://github.com/marshally/planka-cli/issues/22), alongside reads and
native deletion. Extra settings/import/subscription surfaces remain deferred.
See [board API evidence](#board-api-evidence) for verified Community v2.2.1
append, permissions, creation effects, and the source/fixture verification limits.

Basic project creation/update is settled in the style guide's
[project contract](../STYLEGUIDE.md#basic-project-creation-and-updates): default
private creation and supplied-fields-only name/description editing with mutually
exclusive inline/file/stdin input and explicit update-only clearing. Track it in
[issue #23](https://github.com/marshally/planka-cli/issues/23), alongside reads and
native deletion. This slice is implemented; see
[project operations and evidence](#implemented-project-resource-operations).
Ownership transfers and presentation/preferences remain deferred. Native creation
effects need no extra client-side manager writes.

The supported-version floor is settled: target Planka 2.0.0 and higher, with no
Planka 1.x API adapters. This minimum does not establish compatibility with every
later release or edition. Record verified versions and verb/resource capabilities
as implementation proceeds. Future major releases require verification. The
settled [diagnostic contract](../STYLEGUIDE.md#supported-planka-versions) performs
best-effort bootstrap version lookup only after canonical API failures, preserving
the original error/outcome and adding nullable `meta.serverVersion`. It is not an
execution gate or automated edition/capability detector. Track implementation in
[issue #32](https://github.com/marshally/planka-cli/issues/32); no lookup is implemented.

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

## Resolved planning scope

The active additional-management decisions are recorded in
[issue #31](https://github.com/marshally/planka-cli/issues/31). Tasks (#34), read-only
users (#35), board members (#36), basic board management (#22), and basic project
management (#23) now have implementation tickets. Version diagnostics (#32) are
failure-only and preserve the original result. These are planned interfaces; the
implemented command list at the top remains authoritative for current behavior.

Project-manager work (#37), including its remaining specification, stays in its
own ticket at the end of the plan. Account mutations, extra board settings/imports,
and extra project settings/ownership transfers remain explicitly deferred. The
card-member consumer need in #33 is covered by the resource-sized #21; coordinate
it within that resource PR rather than independently implementing the same command.

## API evidence and acceptance limits

Existing tests cover captured board data and a local HTTP fake. The README notes
that API shapes were inherited from Lucenta and that compatibility with other
Planka releases has not been established. Passing these tests proves regression
behavior against those inputs; it does not prove every example works on a live
instance.

Pinned Community bootstrap evidence:
[v2.0.0 presenter](https://github.com/plankanban/planka/blob/v2.0.0/server/api/helpers/bootstrap/present-one.js)
and [v2.2.1 presenter](https://github.com/plankanban/planka/blob/v2.2.1/server/api/helpers/bootstrap/present-one.js)
return `item.version`; the
[v2.2.1 policy](https://github.com/plankanban/planka/blob/v2.2.1/server/config/policies.js)
permits public bootstrap access. This evidence establishes a reported-version
source, not edition or per-operation capability detection, and is not live API
acceptance. Verify endpoint access, shape and version semantics for targeted editions
and releases during diagnostic implementation.

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
3. Select the next unfinished slice using the project's manual board order and live eligibility; nested dispatch/help, card detail, board description, workflow pending criteria, workflow branch name, workflow claim status, the offline workflow guide, workflow next selection, workflow claim, card-member operations, native card operations, native list operations, workflow resume ticket, card task-list operations, label resource operations, comment operations, board resource operations, project resource operations, and workflow create spec are complete.
4. Record that slice's schemas, error/recovery details, and API evidence; add
   meaningful failing acceptance tests, implement, and verify packaged entry points.
5. Update docs and report implemented capabilities, compatibility evidence,
   verification limits, and remaining work in the implementation PR.
