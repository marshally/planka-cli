require "planka/workflow/format"
require "planka/workflow/configuration"
require "planka/cli/failure"
require "planka/cli/command"

module Planka
  module Workflow
    # The single attachment point between workflow commands and shared CLI plumbing.
    module CLI
      ROOT_HELP = <<~HELP
        Workflows:
          workflow claim CARD  Add your membership and move the card to in-progress
          workflow guide  Read built-in agent guidance (offline)
          workflow next  Select queued work without claiming (read-only)
          workflow pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          workflow branch-name CARD  Read the card's branch name (read-only)
          workflow claim-status  Inspect claims across all accessible boards (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka workflow <operation> [arguments] [flags]
          claim CARD  Add your membership and move the card to in-progress
          guide  Read built-in agent guidance (offline)
          next  Select queued work without claiming (read-only)
          pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          branch-name CARD  Read the card's branch name (read-only)
          claim-status  Inspect claims across all accessible boards (read-only)
      HELP
      GUIDE_HELP = <<~HELP
        usage: planka workflow guide [--output human|json]
        Offline: no credentials or network access, even when connection settings are supplied.
        Takes no target or scope flags. Human output is the built-in agent guide.
        JSON uses data/meta/error; data has instructions. Invalid input exits 2.
        Example: planka workflow guide -o json
      HELP
      NEXT_HELP = <<~HELP
        usage: planka workflow next [--board BOARD] [--label LABEL] [--output human|json]
        read-only: selects work from ready-for-agent; does not claim or change resources.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        --board accepts a numeric ID or same-instance board URL; otherwise PLANKA_BOARD_ID is required.
        No mode label: priority by position. feature:SLUG: tickets by creation order.
        effort:SLUG: wayfinder:map and takeable frontier by position.
        Repeated --label values AND-match exactly before selection, including specs/maps.
        At most one distinct feature: or effort: mode label; other labels narrow the queue.
        Completed linked tasks retain blocker handoff/stacking metadata; unfinished ones prevent selection.
        gh must be installed for blocker PR lookup, with authentication for private repositories.
        Unknown/failed PR lookups preserve the recorded branch and an unknown state; malformed results fail.
        No handoff or multiple unmerged blockers yield AMBIGUOUS; an empty queue succeeds.
        Human output matches next-card. JSON uses data/meta/error and the pick, waiting, or frontier schema.
        No --limit, mutation, or collection completeness claim. Failures exit 1 or 2.
        Example: planka workflow next --board 123 --label feature:search -o json
      HELP
      CLAIM_STATUS_HELP = <<~HELP
        usage: planka workflow claim-status [--output human|json]
        Read-only: inspects the signed-in user's claims across all accessible boards.
        Returns the first open claimed card without a PR handoff, or free.
        This does not acquire a lock and makes no GitHub requests.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        No target or board setting is required; PLANKA_BOARD_ID does not restrict scope.
        Human output matches loop-lock; JSON data has held and card, plus claimedAt and ageSeconds when held.
        Failures exit 1 or 2. Example: planka workflow claim-status -o json
      HELP
      BRANCH_NAME_HELP = <<~HELP
        usage: planka workflow branch-name CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Uses the existing feature-label, title-slug, and length rules of branch-name.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        PLANKA_BRANCH_PREFIX optionally reserves room within the 63-character limit.
        Human output is the branch name; JSON data has cardId and branch.
        Failures exit 1 or 2. Example: planka workflow branch-name 123 -o json
      HELP
      PENDING_CRITERIA_HELP = <<~HELP
        usage: planka workflow pending-criteria CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Prints unfinished tasks from lists named exactly "Acceptance criteria", in board-response order.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        JSON data has cardId and criteria; empty criteria are a successful empty array.
        Human output is one criterion per line. Failures exit 1 or 2.
        Example: planka workflow pending-criteria 123 -o json
      HELP

      CLAIM_HELP = <<~HELP
        usage: planka workflow claim CARD [--output human|json]
        Adds the signed-in user's membership, then moves the card to its board's unique in-progress list.
        CARD is a numeric ID or same-instance card URL; no board setting required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Existing membership is retained. Already in-progress cards keep their position; satisfied claims are no-ops.
        JSON uses data/meta/error: card, userId, inProgressListId, claimed, memberAdded, moved; meta.changed reports effects.
        Failures preserve known effects and provide readback-claim recovery; uncertain steps are null.
        Inspect with planka describe card CARD -o json before retrying. This is not an atomic or exclusive lock.
        Exit 0: success; 2: local input; 1: configuration, API, partial or unknown outcome.
        Example: planka workflow claim 123 -o json
      HELP

      def self.branch_preparation(env, **)
        { prefix: Configuration.from_env(env).branch_prefix }
      rescue ConfigurationError => error
        raise Planka::CLI::Failure.new(code: "configuration_error", message: error.message)
      end

      def self.next_preparation(env, instance:, flags:)
        board = flags.fetch(:board, []).first || env["PLANKA_BOARD_ID"]
        if board.to_s.strip.empty?
          raise Planka::CLI::Failure.new(code: "configuration_error", message: "Missing required environment: PLANKA_BOARD_ID (or supply --board BOARD)")
        end
        { board_id: instance.resolve(board, resource: "board", collection: "boards"), labels: flags.fetch(:labels, []).uniq }
      rescue Planka::CLI::Instance::InvalidReference => error
        if flags.fetch(:board, []).empty?
          raise Planka::CLI::Failure.new(code: "configuration_error", message: "PLANKA_BOARD_ID must be a numeric board ID or same-instance board URL")
        end
        raise Planka::CLI::Failure.new(code: "invalid_input", status: 2, message: error.message)
      end

      def self.validate_next_flags(flags)
        boards = flags.fetch(:board, [])
        labels = flags.fetch(:labels, []).uniq
        if boards.uniq.size > 1 || boards.any? { |value| value.strip.empty? } || labels.any? { |value| value.strip.empty? } ||
            labels.count { |label| label.start_with?("feature:", "effort:") } > 1
          "Use one board and at most one feature: or effort: mode label; labels must be nonempty"
        end
      end

      COMMANDS = {
        ["workflow", "claim"] => Planka::CLI::Command.new(resource: "card", collection: "cards", mutation: true, help: CLAIM_HELP, reader: Claim::Card, formatter: Format.method(:claim)),
        ["workflow", "next"] => Planka::CLI::Command.new(reference: false, resource: "board", collection: "boards", flags: { "--board BOARD" => :board, "--label LABEL" => :labels }, validate_flags: method(:validate_next_flags), prepare: method(:next_preparation), help: NEXT_HELP, reader: NextSelection, projector: :as_json.to_proc, formatter: Format.method(:next_selection)),
        ["workflow", "guide"] => Planka::CLI::Command.new(reference: false, session: false, help: GUIDE_HELP, reader: Guide, formatter: Format.method(:guide)),
        ["workflow", "claim-status"] => Planka::CLI::Command.new(resource: "card", collection: "cards", reference: false, help: CLAIM_STATUS_HELP, reader: ClaimStatus, formatter: Format.method(:loop_lock)),
        ["workflow", "pending-criteria"] => Planka::CLI::Command.new(resource: "card", collection: "cards", help: PENDING_CRITERIA_HELP, reader: PendingCriteria, formatter: Format.method(:pending_criteria)),
        ["workflow", "branch-name"] => Planka::CLI::Command.new(resource: "card", collection: "cards", help: BRANCH_NAME_HELP, reader: BranchName, formatter: Format.method(:branch_name), prepare: method(:branch_preparation)),
      }.freeze
      def self.commands = COMMANDS
      def self.groups = { "workflow" => GROUP_HELP }
      def self.root_help = ROOT_HELP
    end
  end
end
