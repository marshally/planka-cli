require "planka/workflow/format"
require "planka/workflow/configuration"
require "planka/cli/failure"

module Planka
  module Workflow
    # The single attachment point between workflow commands and shared CLI plumbing.
    module CLI
      ROOT_HELP = <<~HELP
        Workflows:
          workflow guide  Read built-in agent guidance (offline)
          workflow pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          workflow branch-name CARD  Read the card's branch name (read-only)
          workflow claim-status  Inspect claims across all accessible boards (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka workflow <operation> [arguments] [flags]
          guide  Read built-in agent guidance (offline)
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

      def self.branch_options(env)
        { prefix: Configuration.from_env(env).branch_prefix }
      rescue ConfigurationError => error
        raise Planka::CLI::Failure.new(code: "configuration_error", message: error.message)
      end

      COMMANDS = {
        ["workflow", "guide"] => { reference: false, session: false, help: GUIDE_HELP, reader: Guide, formatter: Format.method(:guide) }.freeze,
        ["workflow", "claim-status"] => { resource: "card", collection: "cards", reference: false, help: CLAIM_STATUS_HELP, reader: ClaimStatus, formatter: Format.method(:loop_lock) }.freeze,
        ["workflow", "pending-criteria"] => { resource: "card", collection: "cards", help: PENDING_CRITERIA_HELP, reader: PendingCriteria, formatter: Format.method(:pending_criteria) }.freeze,
        ["workflow", "branch-name"] => { resource: "card", collection: "cards", help: BRANCH_NAME_HELP, reader: BranchName, formatter: Format.method(:branch_name), options: method(:branch_options) }.freeze,
      }.freeze
      def self.commands = COMMANDS
      def self.groups = { "workflow" => GROUP_HELP }
      def self.root_help = ROOT_HELP
    end
  end
end
