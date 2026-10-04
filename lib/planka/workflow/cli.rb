require "planka/workflow/format"
require "planka/workflow/configuration"
require "planka/cli/failure"

module Planka
  module Workflow
    # The single attachment point between workflow commands and shared CLI plumbing.
    module CLI
      ROOT_HELP = <<~HELP
        Workflows:
          workflow pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          workflow branch-name CARD  Read the card's branch name (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka workflow <operation> [arguments] [flags]
          pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          branch-name CARD  Read the card's branch name (read-only)
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
        ["workflow", "pending-criteria"] => { resource: "card", collection: "cards", help: PENDING_CRITERIA_HELP, reader: PendingCriteria, formatter: Format.method(:pending_criteria) }.freeze,
        ["workflow", "branch-name"] => { resource: "card", collection: "cards", help: BRANCH_NAME_HELP, reader: BranchName, formatter: Format.method(:branch_name), options: method(:branch_options) }.freeze,
      }.freeze
      def self.commands = COMMANDS
      def self.groups = { "workflow" => GROUP_HELP }
      def self.root_help = ROOT_HELP
    end
  end
end
