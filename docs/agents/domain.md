# Domain docs

This is a single-context repository. Domain terms belong in root `CONTEXT.md`;
architectural decisions belong under `docs/adr/`.

## Before codebase exploration

Read `CONTEXT.md` when present, followed by ADRs relevant to the work. If a future
`CONTEXT-MAP.md` exists, follow its pointers to the relevant contexts instead.
Proceed silently when these files are absent. Create them through domain-modeling
as terms or decisions are settled, rather than scaffolding empty documents.

Use glossary terms in issues, proposals, code, tests, and documentation. If a term
is missing, first check existing project language; record a genuine gap for
domain-modeling. Surface conflicts with an ADR explicitly, naming the decision
and the reason to revisit it.

## Document ownership

- [Domain glossary](../../CONTEXT.md): settled resource and workflow terminology.

- [Coding standards](../../CODING_STANDARDS.md): general design and review rules.
- [CLI style guide](../../STYLEGUIDE.md): target CLI behavior and compatibility.
- [Implementation handoff](../CLI_REDESIGN_IMPLEMENTATION.md): current slices,
  architecture, implementation sequence, and verification limits.
- [Workflow module guide](../WORKFLOW_MODULE.md): workflow ownership, library
  loading, and later gem extraction.

Link these sources from the glossary and ADRs instead of copying their contracts.
