# Coding standards

Apply these standards when designing, implementing, refactoring, or reviewing
code. [STYLEGUIDE.md](STYLEGUIDE.md) owns the CLI behavior contract; the
[implementation handoff](docs/CLI_REDESIGN_IMPLEMENTATION.md#canonical-cli-architecture)
and [workflow module guide](docs/WORKFLOW_MODULE.md) describe current ownership.
These standards guide judgment rather than impose method or class size limits.

## Responsibilities and flow

Give each responsibility a clear owner. Parsing, connection settings, reference
resolution, command preparation, execution, and presentation have different
reasons to change. Keep orchestration readable as meaningful ordered stages.
Private methods are appropriate when stages belong to the same module, as in
Parser. Extract a class when it owns a distinct responsibility and hides useful
implementation behind a small interface. Evaluate the resulting ownership and
change cost, rather than the number of lines moved.

Keep each method at a single level of abstraction (SLAP). A method that
coordinates stages names those stages and delegates their detail, as
`Parser#parse` names `parse_options!`, `resolve_command!`, and
`validate_flags!`; it does not also unpack response hashes, validate records
inline, or assemble results between them. When levels mix, extract the
lower-level work into a private method named for its intent. Nested
conditionals that raise different failures at different depths are a common
sign. A method that works entirely at one level, such as a record validator,
may stay long. Give sibling implementations the same stage structure so they
remain comparable.

Preserve ordering constraints when simplifying a flow. For example, help skips
required references but still validates flags and extra arguments. Early returns,
error precedence, and cleanup behavior are observable parts of the contract.

## Interfaces and dependencies

Public messages express the outcome the caller needs; the receiver owns how it
achieves that outcome. Ask Instance to resolve a reference rather than inspecting
its URI fields and duplicating resolution rules. Keep collaborator representation
and internal sequencing private.

Direct dependencies toward stable interfaces. Keep general resource capabilities
independent of workflow conventions. Supply volatile or substitutable
collaborators explicitly; ordinary construction of cohesive internal helpers does
not need an injection framework. Use keyword arguments when positional arguments
make intent or ordering difficult to understand.

Document shared roles through the messages and invariants their implementations
support. Catalogs supply commands, groups, and root_help; callers use that role
rather than branch on concrete catalog classes. Validate external inputs at entry
and trust established internal contracts. Add shared role tests when multiple
implementations need protection against contract drift.

Prefer composition for responsibilities that vary independently. Introduce
inheritance when the relationship supports substitution and a shared contract,
rather than solely to reuse code. Base abstractions on concrete needs. A small
amount of duplication can be clearer than a premature abstraction; remove
forwarding layers that add no ownership or useful information hiding.

## State and validation

Keep temporary values local and retain only state needed across stages. Avoid
caching values already available from another owned value. Capture and freeze
parsed inputs and settings before execution. Immutable data carriers such as
Invocation may expose fields; they need not acquire behavior to justify their
existence.

Validate data where the necessary knowledge lives. Readers validate the response
records they consume. Preparation owns scope defaults and distinguishes explicit
input failures from configuration failures. Classify failures once at that owner;
presentation renders their safe message and status. Session cleanup preserves
the primary outcome.

## Names and compatibility

Use responsibility-based names consistently across code and documentation.
Distinguish resource operations from convention-based workflows. When renaming
internal modules, update references and remove obsolete paths and aliases unless
a documented compatibility contract requires them. The legacy CLI retention
contract remains authoritative and separate from internal Ruby names.

## Tests and review

Verify behavior through public results and effects. Use CLI subprocesses, local
HTTP fixtures, library loading, and installed-package checks as appropriate to
the change. Test private behavior through the public interface. Preserve help,
results, diagnostics, exit status, request ordering, and cleanup when a refactor
promises unchanged behavior. Report fixture verification separately from live
compatibility evidence.

Treat difficult test setup as design feedback: identify the unrelated context an
operation needs and consider whether its dependencies or interface can shrink.
Keep integration coverage when the interaction itself is the contract.

For each architectural review finding, cite the code and this standard, identify
the responsibility or dependency involved, explain a plausible change that makes
its cost visible, and propose the smallest useful correction. Distinguish a
contract violation from a design judgment. Method length, data attributes,
ordinary collection chains, and collaborator construction alone are signals to
investigate, not findings; a long method becomes a finding when it mixes levels
of abstraction, and the finding names the levels it mixes. Consider deletion and
simpler ownership before adding another layer. Report Standards and Spec
findings separately.

## Design references

These are project rules informed by Matt Pocock's codebase-design skill and the
local POODR reviewer skill. The latter synthesizes dependency guidance from POODR
chapter 3, public interfaces from chapter 4, roles from chapter 5, composition and
inheritance from chapters 6–8, and testing from chapter 9. These are paraphrased
principles, not verified quotations from the book.
