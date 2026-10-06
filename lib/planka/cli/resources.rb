require "planka/cli/resources/cards"
require "planka/cli/resources/boards"
require "planka/cli/resources/cards/members"
require "planka/cli/resources/cards/labels"
require "planka/cli/resources/cards/tasks"

module Planka
  module CLI
    # Combines resource-owned command definitions for the shared CLI catalog.
    module Resources
      COMMAND_MODULES = [Cards, Boards, Cards::Members, Cards::Labels, Cards::Tasks].freeze
      ROOT_HELP = "usage: planka <verb> <resource> [reference] [flags]\nResource commands:\n".freeze
      GROUP_HELP = "usage: planka describe <resource> REF [flags]\n".freeze
      COMMANDS = COMMAND_MODULES.flat_map { |catalog| catalog.commands.to_a }.to_h.freeze
      CARD_RELATIONSHIPS = [Cards::Members, Cards::Labels, Cards::Tasks].freeze
      RELATIONSHIP_USAGE = {
        "get" => "usage: planka get <resource> [REF] --card CARD [flags]\n",
        "add" => "usage: planka add <resource> REF --card CARD [flags]\n",
        "remove" => "usage: planka remove <resource> REF --card CARD [flags]\n",
        "update" => "usage: planka update <resource> REF --card CARD [flags]\n",
      }.freeze
      GROUPS = { "describe" => GROUP_HELP + Cards::GROUP_HELP + Boards::GROUP_HELP }.merge(
        RELATIONSHIP_USAGE.to_h { |verb, usage| [verb, usage + CARD_RELATIONSHIPS.filter_map { |resource| resource::GROUP_HELP[verb] }.join] }
      ).freeze

      def self.commands = COMMANDS
      def self.groups = GROUPS
      def self.root_help = ROOT_HELP + COMMAND_MODULES.map(&:root_help).join
    end
  end
end
