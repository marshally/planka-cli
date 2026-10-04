# Workflow module and future gem extraction

Agent conventions live in `Planka::Workflow` inside the existing gem. The module
is designed to become a separately published gem, initially in this repository
or later in another repository. Separate packaging and versioning are deferred.

## Loading and dependency direction

```ruby
require "planka"          # General client, resource models, and operations
require "planka/workflow" # Agent conventions and workflow operations
```

Core loading does not load workflows or CLI code. Workflow loading does not load
CLI code, fetch environment settings, authenticate, or issue requests.

The dependency direction is workflows to core. The bundled CLI selects both;
core models and administration readers do not depend on workflow conventions.
Workflow implementations live under `lib/planka/workflow/`.

## Ownership and interfaces

| Module | Owns |
| --- | --- |
| `Planka::Client` | HTTP requests and authenticated session lifecycle. |
| `Planka::Board`, `Planka::Card` | General lists, labels, tasks, memberships, card references, and native list types. |
| `Workflow::Board`, `Workflow::Card` | Interpret core snapshots using agent conventions: ticket/spec classification, ready/in-progress lists, acceptance criteria, feature labels, claims, and blockers. |
| Workflow operations | Branch naming, pending criteria, queue selection, claiming, claim inspection, blocking links, spec/ticket publishing, handoff interpretation, and completed specs. |
| `Workflow::Configuration` | Explicitly captures workflow settings from a supplied environment. Branch-prefix validation belongs here, independently of connection settings. |
| `Workflow::Format` | Workflow human text and legacy result projections, without IO or session ownership. |
| `Workflow::CLI` | Workflow command definitions, help, formatters, and conversion of workflow configuration failures into canonical CLI failures. |
| Shared CLI modules | Parsing, connection/reference validation, session coordination, canonical envelopes, diagnostics, and exit handling. |

API-backed workflow readers accept an authenticated client and explicit inputs:

```ruby
Planka::Workflow::PendingCriteria.read(client, card_id, base_url: base_url)
Planka::Workflow::BranchName.read(client, card_id, base_url: base_url, prefix: prefix)
Planka::Workflow::ClaimStatus.read(client, base_url: base_url)
```

`Planka::Workflow::Guide.read` returns built-in instructions without a client or
settings. Its canonical command executes before connection validation or session
creation. Legacy `Prime` retains its original instructions separately.

Pure selection algorithms accept workflow board/card interpretations and their
existing external dependencies. Construct a workflow board from a general board
with `Planka::Workflow::Board.new(board)`. Core cards expose resource data;
workflow cards expose convention decisions such as `ticket?` and `takeable?`.

Workflow implementations return results or structured failures. They do not
open authenticated sessions, read credentials from the environment, print, or
exit the process. Legacy claim, lock inspection, and spec-completion orchestration
are owned by workflow operations; their executables adapt inputs and results.
Claim returns its data and the original card reference so the legacy human and
JSON projections preserve their respective records. Partial publishing failures
retain the existing recovery state through the shared `Planka::PartialFailure`.

## CLI attachment and compatibility

`require "planka/workflow/cli"` loads the workflow CLI adapter. The bundled
executable passes it to `CanonicalCLI.run` through `extensions:`. An extension
provides `commands`, `groups`, and `root_help`; command definitions select a
reader, callable formatter, and optional pre-session settings function. Commands
without references select `reference: false`; offline commands additionally select
`session: false` and their readers take no client or settings. Shared
parsing and output contain no workflow command names or branch-prefix rules.

Historical workflow Ruby paths and constant aliases are removed. There is no
legacy Ruby loader or formatting forwarding module. Ruby callers use
`Planka::Workflow` directly and load CLI presentation explicitly when needed.
The bundled executables retain the legacy CLI contracts while calling current
workflow interfaces; environment defaults are supplied by those executables,
not by library compatibility wrappers. The core `require "planka"` entry point
loads only general capabilities.

All 21 flat commands and direct executables retain their existing arguments,
effects, output, and exit contracts. No canonical operations, warning policy,
naming rules, or deletion behavior change as part of this restructuring.

## Later extraction

Create a workflow gemspec that owns workflow implementation, CLI integration,
and declares a dependency on the core library.
Keep the core library and shared CLI machinery available without a workflow
dependency. The CLI distribution can depend on both packages and keep the
existing `planka workflow ...` grammar. Decide package names, version constraints,
and release automation when extraction is requested.

Before publishing separate packages, build and install them in isolation and
verify the loading and dependency direction with only their declared files and
dependencies. The current module layout prepares that work; it does not prove
independent gem installation or publication yet.

## Verification seams

Preserve the existing subprocess and local HTTP acceptance tests for canonical
and legacy commands, including read/write boundaries and partial failures. Add
isolated Ruby subprocess checks at the explicitly approved library-loading seam.
The fixture and package checks do not establish live Planka compatibility.
