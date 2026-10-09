module Planka
  module Workflow
    # Current onboarding guidance; the legacy Prime text retains its own contract.
    module Guide
      INSTRUCTIONS = <<~'MARKDOWN'.freeze
        # planka-cli agent guide

        Start with `planka workflow guide`; use `planka <command> --help` for options.

        ## Connection and output
        API commands require PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, and
        PLANKA_AGENT_PASSWORD from the caller's environment. References accept IDs
        or same-instance URLs; names need resource scope. Help/guide/version work
        offline. Never report credentials.

        Add `-o json` for canonical results: one document with data, meta, and
        error. Check status: 0 success, 2 invalid input, 1 other failure. Diagnostics
        go to stderr.
        Legacy JSON/exits remain unchanged.

        ## Find and work a ticket
        1. `planka describe board BOARD -o json`: inspect lists, cards, and tasks.
        2. `planka workflow next --board BOARD -o json`: select an unclaimed,
           unblocked, unquarantined ticket in ready-for-agent. Add `--label feature:SLUG` for
           ticket order or `--label effort:SLUG` for map/frontier; repeated labels
           AND-match; PLANKA_BOARD_ID is the default scope. Empty queues are normal.
        3. `planka describe card CARD -o json`: inspect description, criteria,
           blockers, comments, and memberships before acting.
        4. `planka workflow claim-status -o json`: inspect your first open claim
           without a latest PR handoff across all accessible boards. No lock or GitHub check. When authorized,
           `planka workflow claim CARD -o json` adds membership and moves
           the card to in-progress. Reclaiming an already-satisfied card is a no-op.
           On partial/unknown outcomes, inspect the card before retrying;
           membership and move are separate writes, not an exclusive lock.
        5. `planka workflow branch-name CARD` supplies a branch slug;
           PLANKA_BRANCH_PREFIX optionally reserves room, without being prepended.
           `planka workflow pending-criteria CARD -o json` lists unfinished tasks
           in Acceptance criteria. Workflow next's parent field identifies
           the stacking branch; resolve AMBIGUOUS before branching. GitHub PR
           checks require authenticated gh.
        6. `planka create comment --card CARD --text "TEXT" -o json`: handoff
           using `Branch: BRANCH` and `PR: URL` on separate lines.

        ## Publish and recover
        Boards: `get boards --project PROJECT`, `get|update|delete board BOARD`,
        `create board --project PROJECT --name NAME`. Deletion removes board contents.
        Projects: `planka get projects`, `get|update|delete project PROJECT`,
        `create project --name NAME`. Deletion requires an empty project.
        Resources: `planka get cards|lists|labels --board BOARD`,
        `get|update|delete card|list REF`, `create card --list LIST --name NAME`,
        `create list --board BOARD --name NAME`, `move card CARD --list LIST`.
        Closing a list completes tasks linking its cards. Assignments use
        `get|add|remove member USER --card CARD` and `get members --card CARD`;
        `add|remove label LABEL --card CARD` skips satisfied assignments.
        `create label --board BOARD --name NAME --color COLOR` always creates;
        `get|update|delete label LABEL --board BOARD` manages existing labels.

        `planka workflow create spec --list LIST --name NAME` publishes a project
        card without Acceptance criteria. `workflow create ticket` also requires
        `--criteria-file FILE` (a JSON string array) and creates incomplete tasks
        in input order. Share feature:SLUG labels. `--description-file FILE`
        preserves text; one file may use - for stdin.
        Positions append. `planka link BLOCKED BLOCKER` records linked
        tasks in Blocked by; repeating a link is safe. Read help before writes.

        For an unknown outcome, read the board back before retrying: the write
        may already have applied. Legacy recovery JSON can contain completed=false,
        error, reconcile, and created resources. Resume a partial ticket with
        `planka workflow resume ticket CARD --criteria-file FILE`.
      MARKDOWN

      def self.read = { "instructions" => INSTRUCTIONS }
    end
  end
end
