module Planka
  # Built-in guidance, independent of instance credentials and live board state.
  module Prime
    INSTRUCTIONS = <<~'MARKDOWN'.freeze
      # planka-cli agent guide

      Run `planka prime` at session start or after context compaction.
      Use `planka <command> --help` for full options; direct `planka-<command>`
      executables accept the same arguments. `planka --version` reports the version.

      ## Connection and output
      Board operations use resolved environment credentials: PLANKA_BASE_URL,
      PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD. PLANKA_BOARD_ID selects the board
      for next-card and the default board for snapshot, labels, and board creates.
      Card operations derive their board from CARD, a numeric ID or card URL.
      Prime and help work offline. Keep credential values out of reports.

      Add `--output json` when consuming results programmatically. Default output
      is for people; diagnostics go to stderr and failures exit nonzero. Inspect
      exit status before consuming stdout, including when piping to jq.

      ## Find and work a ticket
      1. `planka snapshot --output json`: inspect lists, cards, labels, and tasks.
      2. `planka next-card --output json`: pick the top unclaimed, unblocked ticket
         in ready-for-agent. Add `feature:SLUG` for a feature's ticket order, or
         `effort:SLUG` for its map/frontier. No available card is a normal result.
      3. `planka show CARD --output json`: read description, criteria, blockers,
         comments, and membership before acting.
      4. When authorized to start, `planka claim CARD --output json` adds your
         membership and moves the card to in-progress. `planka loop-lock` reports
         your open claim without a PR handoff across all visible boards.
      5. `planka branch-name CARD` supplies a branch slug (PLANKA_BRANCH_PREFIX is
         optional); `planka unticked CARD --output json` lists remaining criteria.
         next-card's parent field identifies the stacking branch; resolve an
         AMBIGUOUS parent before branching. GitHub PR checks require authenticated gh.
      6. Record handoff with `planka comment CARD "TEXT" --output json`, placing
         `Branch: BRANCH` and `PR: URL` on separate lines in TEXT.

      ## Publish and maintain work
      Specs have no Acceptance criteria task list; tickets have one. Share
      `feature:SLUG` labels to associate them. Use `planka create-spec` or
      `planka create-ticket`; both take `--list ID_OR_NAME --title TITLE`.
      Tickets also require `--criteria-file FILE`: a JSON array of strings.
      `--description-file FILE` accepts multiline text; either file option accepts
      `-` for stdin. Omitted positions append to the queue.

      `planka labels`, `planka create-label`, and `planka apply-label` manage labels.
      `planka link BLOCKED BLOCKER` records dependencies as linked tasks in
      Blocked by; repeating a link is safe. Use IDs for ambiguous list/label names.
      `planka update-card` edits title/description; `planka move-card` moves without
      claiming. `planka create-task-list` and `planka rename-task-list` manage lists.
      `planka create-list` adds board columns. When authorized, `planka spec-sweep`
      comments and moves finished specs to done across all visible boards.

      ## Recover a failed write
      For an unknown outcome, read the board back before retrying: the write may
      already have applied. JSON recovery output may include completed=false,
      error, reconcile, and resources created so far. Resume partial tickets with
      `planka create-ticket --card CARD --criteria-file FILE --output json`.
    MARKDOWN
  end
end
