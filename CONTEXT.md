# Planka CLI domain

The language of Planka resources and the project conventions layered on them.
Definitions here summarize settled terms and link to their authoritative contracts.

## Language

### Commands and resources

**Resource command**:
A command that reads or changes native Planka resources or their relationships
directly, without requiring project workflow conventions. [Source](STYLEGUIDE.md#command-grammar)
_Avoid_: Administrative command, admin command.

**Workflow command**:
A command that interprets or applies project conventions to Planka resources,
such as work selection, acceptance criteria, claims, or blocker handoffs. [Source](STYLEGUIDE.md#workflow-commands)

**Card**:
A native Planka resource organized in a board list; tickets, specs, and effort
maps are workflow interpretations of cards. [Source](README.md#workflow-examples)
_Avoid_: Ticket when referring to cards generally.

**User**:
A Planka account that exists independently of assignment to any card.
[Source](STYLEGUIDE.md#card-members)

**Card member**:
A user assigned to a particular card. Adding membership alone does not move the
card or perform the workflow claim operation. [Source](STYLEGUIDE.md#card-members)

**Card membership**:
The relationship connecting a user to a card; distinct from the user account.
[Source](STYLEGUIDE.md#card-members)
_Avoid_: Membership ID when identifying the user in a card-member command.

**Board member**:
A user with a native board membership granting an editor or viewer role, with
optional comment permission for viewers. [Source](STYLEGUIDE.md#board-members)
_Avoid_: Card member when referring to board access.

**Project manager**:
A user granted management access through the native project-manager relationship,
separate from board membership. [Source](STYLEGUIDE.md#project-managers)
_Avoid_: Project member as a synonym for project manager.

**Ticket**:
A workflow card with a task list named exactly `Acceptance criteria`, representing
work with explicit criteria for acceptance. [Source](README.md#workflow-examples)
_Avoid_: Task, card when the ticket distinction matters.

**Spec**:
A project card without an `Acceptance criteria` task list, describing the work
associated with a feature rather than a selectable ticket. [Source](README.md#workflow-examples)
_Avoid_: Specification document when referring to the card.

**Acceptance criterion**:
An individual task in a card's `Acceptance criteria` task list, expressing a
condition for accepting the work. [Source](README.md#canonical-pending-criteria)
_Avoid_: Ticket, blocker.

**Pending criterion**:
An acceptance criterion that is not marked complete. [Source](README.md#canonical-pending-criteria)
_Avoid_: Pending ticket.

### Work selection and ownership

**Ready**:
The workflow state of a card in the list named `ready-for-agent`; readiness alone
does not mean the card is unclaimed or unblocked. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Takeable as a synonym for ready.

**In progress**:
The workflow state of a card in the list named `in-progress`, where the claim
operation moves work being undertaken. [Source](STYLEGUIDE.md#workflow-commands)
_Avoid_: Claimed as a synonym for list placement.

**Claim**:
A user's card membership interpreted as ownership of work; the claim operation
also moves the card into progress. [Source](STYLEGUIDE.md#workflow-commands)
_Avoid_: Exclusive lock, reservation acquired by selection.

**Claim status**:
The inspection of whether the signed-in user has an open claimed card without a
latest PR handoff, across accessible boards. [Source](README.md#canonical-claim-status)
_Avoid_: Lock acquisition, GitHub PR status.

**Takeable card**:
A ready card with no members and no incomplete linked blocker tasks; ticket
queues additionally require it to be a ticket. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Ready as a synonym for takeable.

**Priority queue**:
Ready tickets ordered by board-list position, reflecting the human's priority
order rather than ticket creation order. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)

**Feature**:
A grouping of related specs and tickets identified by a shared `feature:<slug>`
label, whose ticket queue follows creation order. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Effort as a synonym for feature.

**Effort**:
A grouping of wayfinding cards identified by a shared `effort:<slug>` label,
organized as maps and a takeable frontier. [Source](README.md#canonical-next-work)
_Avoid_: Feature as a synonym for effort.

**Effort map**:
A card labelled `wayfinder:map` within an effort, representing the map rather
than a frontier candidate. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Spec as a synonym for map.

**Frontier**:
An effort's takeable non-map cards ordered by position; frontier cards need not
have acceptance criteria. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Feature ticket queue.

### Dependencies and handoffs

**Blocker**:
A card that another card depends on, represented by a linked task on the dependent
card; an incomplete linked task prevents that dependent card being takeable. [Source](README.md#canonical-next-work)
_Avoid_: Blocked card when referring to its prerequisite.

**Blocked card**:
A card with at least one incomplete linked blocker task. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Blocker when referring to the dependent card.

**Handoff**:
A card comment identifying the work's branch through a `Branch:` line, with an
optional `PR:` line identifying its pull request. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: PR as a synonym for every handoff.

**Latest handoff**:
The newest comment containing a branch handoff; a newer branch-only handoff
supersedes an older handoff with a PR. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-fifth-slice-claim-status)

**Parent branch**:
The branch selected as the base for a ticket's work from its blockers' handoffs
and merge states, or an ambiguous result when that base cannot be determined. [Source](docs/CLI_REDESIGN_IMPLEMENTATION.md#implemented-seventh-slice-next-work)
_Avoid_: Ticket branch, Planka parent card.
