module Planka
  module Workflow
    # Current onboarding guidance; the legacy Prime text retains its own contract.
    module Guide
      INSTRUCTIONS = <<~'MARKDOWN'.freeze
        # planka-cli agent guide

        Run `planka workflow guide` at session start or after context compaction.
        Use `planka <command> --help` for full options; `planka --help` lists
        implemented commands and `planka --version` reports the version.

        ## Connection and output
        API commands require PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, and
        PLANKA_AGENT_PASSWORD from the caller's environment. Canonical card/board
        reads require an explicit numeric ID or same-instance URL. Guide, help,
        and version work offline. Keep credential values out of reports.

        Add `-o json` for canonical results: one document with data, meta, and
        error. Inspect the exit status before consuming stdout: 0 is success,
        2 is invalid input, and 1 is another failure. Diagnostics go to stderr.
        Commands below marked legacy retain their bare JSON and existing exits;
        they are deprecated and retained indefinitely, without runtime warnings.

        ## Find and work a ticket
        1. `planka describe board BOARD -o json`: inspect lists, cards, and tasks.
        2. `planka workflow next --board BOARD -o json`: select an unclaimed,
           unblocked ticket in ready-for-agent. Add `--label feature:SLUG` for
           ticket order or `--label effort:SLUG` for map/frontier; repeated labels
           AND-match. Without --board, PLANKA_BOARD_ID supplies scope. No available
           card is a normal result.
        3. `planka describe card CARD -o json`: inspect description, criteria,
           blockers, comments, and memberships before acting.
        4. `planka workflow claim-status -o json`: inspect your first open claim
           without a latest PR handoff across all accessible boards. This neither
           acquires a lock nor checks GitHub. When authorized to start,
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
        6. `planka comment CARD "TEXT" --output json` (legacy): record handoff
           with `Branch: BRANCH` and `PR: URL` on separate lines in TEXT.

        ## Publish and recover
        Card assignments use `planka get members --card CARD`,
        `planka get member USER --card CARD`, `planka add member USER --card CARD`,
        and `planka remove member USER --card CARD`. USER is an ID, same-instance
        user URL, or exact name among the card's board members. These operations
        preserve list placement; use workflow claim to move work into progress.
        Satisfied add/remove operations are no-ops. Unknown outcomes require
        reading the members back before retrying. Board-member commands are planned.

        Publishing still uses legacy commands. Specs have no
        Acceptance criteria list; tickets have one. Share feature:SLUG labels.
        `planka create-spec` and `planka create-ticket` take --list ID_OR_NAME and
        --title TITLE; tickets require --criteria-file FILE (a JSON string array).
        --description-file FILE accepts multiline text; either file accepts -
        for stdin. Omitted positions append. `planka link BLOCKED BLOCKER`
        records linked tasks in Blocked by; repeating a link is safe. Use IDs
        for ambiguous names. Read command help before making an authorized write.

        For an unknown outcome, read the board back before retrying: the write
        may already have applied. Legacy recovery JSON can contain completed=false,
        error, reconcile, and created resources. Resume a partial ticket with
        `planka create-ticket --card CARD --criteria-file FILE --output json`.
      MARKDOWN

      def self.read = { "instructions" => INSTRUCTIONS }
    end
  end
end
