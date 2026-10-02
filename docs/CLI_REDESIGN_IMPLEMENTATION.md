# CLI redesign implementation handoff

## State and intent

The goal is a general Planka administration CLI with a kubectl-like
`planka <verb> <resource> [reference] [flags]` interface. Convention-based agent
operations live under `planka workflow`.

This PR changes documentation only. No nested command dispatcher,
additional administration operations have been
implemented. README's **Current interface** describes working commands; its
**Usage — planned interface** section describes the target.

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
| [lib/planka/cli.rb](../lib/planka/cli.rb) | Option parsing, output formatting, scope helpers, and recovery/error plumbing. |
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

## First task: nested dispatch and one read-only vertical slice

Deliver `planka describe card CARD` using the existing card-detail behavior,
along with root, `describe`, and leaf help. Keep every current command and direct
executable callable. This slice establishes command routing and compatibility
without requiring new API endpoints, configuration storage, or mutation behavior.

Before changing implementation, record the first leaf's JSON schema and successful
human output contract. Canonical output uses the approved `data`/`meta`/`error`
envelope: put the existing card-detail object in `data`, with `meta: {}` and
`error: null` on success. Preserve the unwrapped legacy `show` JSON shape and test
the two contracts independently. Use the approved error/recovery rules in the
style guide and document the leaf's applicable error codes.

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
   release notes with implemented behavior. Deprecate legacy entry points only
   under a separately documented compatibility policy.

For every mutation slice, verify supplied-fields-only updates, idempotent
relationships where applicable, unknown outcomes, partial completion, and readback.
Do not rewrite retry behavior merely as a side effect of reorganizing commands.

## Open decisions

These choices are not settled by the example invocations. Resolve the relevant
ones in the implementation slice before claiming its contract is complete.

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

| Decision | Required outcome |
| --- | --- |
| Pagination/filtering | Establish actual API pagination and supported filters; define completeness, ordering, and user-facing flags. |
| Supported versions | State tested Planka editions/versions and the supported verb/resource matrix. |
| Deletion | Establish cascades and whether each destructive operation needs confirmation; define noninteractive behavior and `--yes` if required. |
| Legacy deprecation | Choose release timing, notice policy, and removal conditions for flat/direct executables and their schemas. |

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

## Resume checklist

1. Read the style guide, this handoff, and current README implementation labels.
2. Inspect current refs and source; do not assume this snapshot is still current.
3. Select the bounded first task or the next unfinished slice from its successor PR.
4. Record that slice's unresolved contracts, add meaningful failing acceptance
   tests, implement, and verify the packaged entry points.
5. Update docs and report implemented capabilities, compatibility evidence,
   verification limits, and remaining work in the implementation PR.
