# Changelog

## Unreleased

Added `planka describe card CARD` (also `describe cards`) with nested help and
common `-o`/`--output` flags. Human output matches `show`; JSON uses the canonical
`data`/`meta`/`error` envelope. Input and required environment are validated
before authentication. API errors use stable codes and omit raw server bodies.

All 21 flat commands and direct executables are deprecated and retained
indefinitely with their existing arguments, effects, JSON, and exit behavior.
Help labels deprecation; there are no automatic runtime warnings. `show` has
an implemented replacement in `describe card`; other canonical operations
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
