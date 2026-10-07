require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Boards
        ROOT_HELP = "  describe board BOARD  Read board snapshot and related data (read-only)\n".freeze
        GROUP_HELP = "  board BOARD  Read board snapshot and related data (read-only)\n".freeze
        HELP = <<~HELP
          usage: planka describe board BOARD [--output human|json]
          Read-only: board ID or same-instance board URL; an explicit target is required.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Human output matches snapshot. JSON uses data/meta/error; failures exit 1 or 2.
          Example: planka describe board 123 -o json
        HELP

        def self.format(snapshot)
          lines = ["Board #{snapshot.fetch("boardId")}"]
          lists = Array(snapshot["lists"])
          cards = Array(snapshot["cards"])
          if lists.empty? && snapshot["listId"]
            lines << "List #{snapshot.fetch("listId")}:"
            lines.concat(cards.map { |card| "  - #{card["name"]} (#{card["url"]})" })
          else
            lists.each do |list|
              lines << "#{list["name"]} (#{list["type"]}):"
              in_list = cards.select { |card| card["listId"] == list["id"] }
              lines.concat(in_list.empty? ? ["  none"] : in_list.map { |card| "  - #{card["name"]} (#{card["url"]})" })
            end
          end
          lines.join("\n")
        end

        COMMANDS = {
          ["describe", "board"] => Command.new(aliases: [["describe", "boards"]], resource: "board", collection: "boards", help: HELP, operation: Planka::Boards::Snapshot.method(:read), formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
