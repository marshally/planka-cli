require "planka"
require "planka/cli"

module Planka
  module CLI
    # Administration command definitions, independent of workflow conventions.
    module Administration
      ROOT_HELP = <<~HELP
        usage: planka <verb> <resource> [reference] [flags]
        Administration:
          describe card CARD  Read card details and related data (read-only)
          describe board BOARD  Read board snapshot and related data (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka describe <resource> REF [flags]
          card CARD  Read card details and related data (read-only)
          board BOARD  Read board snapshot and related data (read-only)
      HELP
      LEAF_HELP = <<~HELP
        usage: planka describe card CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
        Example: planka describe card 123 -o json
      HELP

      BOARD_HELP = <<~HELP
        usage: planka describe board BOARD [--output human|json]
        Read-only: board ID or same-instance board URL; an explicit target is required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Human output matches snapshot. JSON uses data/meta/error; failures exit 1 or 2.
        Example: planka describe board 123 -o json
      HELP

      COMMANDS = {
        ["describe", "card"] => { aliases: [["describe", "cards"]], resource: "card", collection: "cards", help: LEAF_HELP, reader: Planka::CardDetail, formatter: Planka::CLI.method(:card_detail) }.freeze,
        ["describe", "board"] => { aliases: [["describe", "boards"]], resource: "board", collection: "boards", help: BOARD_HELP, reader: Planka::Snapshot, formatter: Planka::CLI.method(:board_snapshot) }.freeze,
      }.freeze
      GROUPS = { "describe" => GROUP_HELP }.freeze

      def self.commands = COMMANDS
      def self.groups = GROUPS
      def self.root_help = ROOT_HELP
    end
  end
end
