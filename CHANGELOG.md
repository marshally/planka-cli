# Changelog

## Unreleased

Separated canonical CLI catalogs, parsing, immutable invocations, captured
connection settings, instance reference resolution, and command preparation.
Reader inputs and scope validation finish before sessions open. Workflow
preparation owns default-scope error classification. Command behavior, output,
errors, legacy contracts, and library loading remain unchanged.

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
