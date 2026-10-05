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
`planka workflow next`; the eighth adds `planka workflow claim CARD`. All legacy entry
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
| [lib/planka/client.rb](../lib/planka/client.rb) | HTTP endpoints, session lifecycle, retries, and unknown-write-outcome detection. |
| [lib/planka/card_detail.rb](../lib/planka/card_detail.rb), [lib/planka/snapshot.rb](../lib/planka/snapshot.rb) | Existing detailed card and board/list read models. |
| [lib/planka/workflow/publishing.rb](../lib/planka/workflow/publishing.rb), [lib/planka/labels.rb](../lib/planka/labels.rb), [lib/planka/lists.rb](../lib/planka/lists.rb), [lib/planka/task_lists.rb](../lib/planka/task_lists.rb) | Existing publishing and resource operations. |
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
reusing them. Reading board IDs through the projects response does not establish
a complete project or board resource interface.

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
rule. Closed cards and claims by other users do not hold this gate. There are
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
label, ready-for-agent tickets are selected by position, excluding claimed and
unfinished-blocked cards. A feature mode uses ticket creation order and numbers
the matching feature tickets starting at one. Specs/maps must also match all
supplied labels; blocker lookup retains the original board even when the blocker
does not match filters. An effort mode returns wayfinder:map cards and takeable
frontier cards by position. It performs no handoff or GitHub lookup.

Human output is the existing pick, waiting, or frontier report. JSON contains
that report's existing projection in `data`, with `meta: {}` and `error: null`:

- Pick: `card`, `specs`, `number` (null for priority), `blockers`, and `parent`.
  Card references have `id`, `name`, `url`. Each blocker has `card`, `branch`,
  `pullRequest`, and `pullRequestState` (nullable).
- Waiting: `card: null` and `waiting`, whose card references add `claimed` and
  `blockedBy` card references. Empty waiting succeeds with an empty array.
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
indefinitely; help names the replacement without runtime warnings.

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
validation; [Claim::Progress](../lib/planka/workflow/claim/progress.rb) owns confirmed
and uncertain effects, result projection, and recovery state. Both write steps
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
one retry includes DELETE. Membership removal disables both that retry and blind
client retries using `idempotent: false`. Existing idempotent requests retain their
policy. Development checks use Bundler 4.0.14 with the unchanged lockfile;
supported dependency/Ruby ranges still come from the gemspec and CI.

Public subprocess/local HTTP tests cover reads, exact target writes, no-ops,
names/URLs/scopes, filters/limits/completeness, malformed inputs and responses,
uncertain writes/readback, failure categories, cleanup, and offline help. Package
checks exercise installed commands outside the checkout. No live writes were
authorized or performed; subscription/activity effects are source evidence only.

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
| [CLI::Resources](../lib/planka/cli/resources.rb), [Workflow::CLI](../lib/planka/workflow/cli.rb) | Separate command catalogs own paths, aliases, help, applicable flags, local validation, readers, presentation, and command-specific preparation. |
| [CLI::Catalog](../lib/planka/cli/catalog.rb) | Combine resource commands with explicitly attached catalogs and resolve declared aliases. Own root/group/leaf help selection. |
| [CLI::Parser](../lib/planka/cli/parser.rb) | `parse` owns mutable option parsing and local syntax validation, returning an immutable invocation. No configuration or execution. |
| [CLI::Invocation](../lib/planka/cli/invocation.rb) | Immutable snapshot of the selected definition, program, output format, reference, flags, and optional help text. No parsing, environment access, preparation, or execution. |
| [CLI::Configuration](../lib/planka/cli/configuration.rb) | `from_env` captures required connection settings and provides session arguments. Credentials are frozen and inspection is redacted. Owns a validated instance, not resource-reference resolution. |
| [CLI::Instance](../lib/planka/cli/instance.rb) | Own the validated server URL, including instance path, and `resolve` numeric IDs or same-instance resource URLs. No credentials, environment defaults, or command policy. |
| [CLI::PreparedCommand](../lib/planka/cli/prepared_command.rb) | `build` validates configuration, resolves explicit references, invokes catalog preparation, and captures executable reader arguments before authentication. Offline commands require no connection settings. `execute` accepts the session client. |
| [CLI::Output](../lib/planka/cli/output.rb), [CLI::Failure](../lib/planka/cli/failure.rb) | Render canonical envelopes, catalog-selected human/JSON presentation, safe diagnostics, and statuses. Expected failures can carry known data/metadata. |
| [Client](../lib/planka/client.rb) | Own HTTP/session lifecycle. Accept explicit connection settings; canonical sessions opt into response-document and token validation. |
| Canonical readers | Read and validate only the records their operation needs. Return resource data or existing workflow reports; catalogs select result projections. |

The coordinator now follows parse → prepare → open session when required →
execute → render. Help returns after parsing. Offline guide preparation captures
its reader without inspecting connection settings or opening a session.
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
and immutable parsed flags, and return reader keyword arguments. Reader/client
inputs are captured before the session starts. General positional references are
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
Do not rewrite retry behavior merely as a side effect of reorganizing commands.

## Settled decisions and implementation deliverables

The resource-sized [lists issue #18](https://github.com/marshally/planka-cli/issues/18)
now has a settled update-field contract. See the style guide’s
[list updates](../STYLEGUIDE.md#list-updates); implementation and API acceptance
remain outstanding.

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

Basic board creation/update is settled in the style guide's
[board contract](../STYLEGUIDE.md#basic-board-creation-and-updates): project/name
creation with optional position and append default, and name/position updates
within the existing project. Track it in
[issue #22](https://github.com/marshally/planka-cli/issues/22), alongside reads and
native deletion. Extra settings/import/subscription surfaces remain deferred;
create/update are not implemented. Verify native append, permissions, creation
side effects and per-version/edition support during implementation.

Basic project creation/update is settled in the style guide's
[project contract](../STYLEGUIDE.md#basic-project-creation-and-updates): default
private creation and supplied-fields-only name/description editing with mutually
exclusive inline/file/stdin input and explicit update-only clearing. Track it in
[issue #23](https://github.com/marshally/planka-cli/issues/23), alongside reads and
native deletion. Ownership transfers and presentation/preferences remain deferred;
create/update are not implemented. Verify native permissions, limits, creation
effects and per-version/edition support during implementation; no extra
client-side manager writes.

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
3. Select the next unfinished slice using the project's manual board order and live eligibility; nested dispatch/help, card detail, board description, workflow pending criteria, workflow branch name, workflow claim status, the offline workflow guide, workflow next selection, workflow claim, and card-member operations are complete.
4. Record that slice's schemas, error/recovery details, and API evidence; add
   meaningful failing acceptance tests, implement, and verify packaged entry points.
5. Update docs and report implemented capabilities, compatibility evidence,
   verification limits, and remaining work in the implementation PR.
