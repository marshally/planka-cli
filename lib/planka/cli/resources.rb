require "planka/cli/resources/cards"
require "planka/cli/label_relationship"
require "planka/cli/resources/boards"
require "planka/cli/resources/cards/members"

module Planka
  module CLI
    # Combines resource-owned command definitions for the shared CLI catalog.
    module Resources
      COMMAND_MODULES = [Cards, Boards, Cards::Members, CardLabels].freeze
      ROOT_HELP = "usage: planka <verb> <resource> [reference] [flags]\nResource commands:\n".freeze
      GROUP_HELP = "usage: planka describe <resource> REF [flags]\n".freeze
      COMMANDS = COMMAND_MODULES.flat_map { |catalog| catalog.commands.to_a }.to_h.freeze
      GROUPS = { "describe" => GROUP_HELP + Cards::GROUP_HELP + Boards::GROUP_HELP }.merge(Cards::Members.groups).merge(CardLabels.groups) { |_key, existing, added| existing + "\n" + added }.freeze

      def self.commands = COMMANDS
      def self.groups = GROUPS
      def self.root_help = ROOT_HELP + COMMAND_MODULES.map(&:root_help).join
    end
  end
end
