# Changelog

## Unreleased

Added publishing and reading commands so an agent can create and verify specs
and tickets without the MCP server or ad hoc REST: `snapshot`, `show`,
`create-list`, `create-spec`, `create-ticket`, `update-card`, `move-card`,
`labels`, `create-label`, `apply-label`, `create-task-list` and
`rename-task-list`. All
emit JSON on stdout. Creates no longer retry once their outcome is unknown, so a
timeout cannot silently duplicate a card.

## 0.1.0

Extracted Planka Ruby workflows from Lucenta; added configurable instance, board and branch prefix, gem packaging, and the `planka` command.
