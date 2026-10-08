require "planka/cli/resources/cards"
require "planka/cli/resources/boards"
require "planka/cli/resources/lists"
require "planka/cli/resources/labels"
require "planka/cli/resources/cards/members"
require "planka/cli/resources/cards/labels"
require "planka/cli/resources/cards/tasks"
require "planka/cli/resources/cards/task_lists"

module Planka
  module CLI
    # Combines resource-owned command definitions for the shared CLI catalog.
    module Resources
      COMMAND_MODULES = [Cards, Boards, Lists, Labels, Cards::Members, Cards::Labels, Cards::TaskLists, Cards::Tasks].freeze
      ROOT_HELP = "usage: planka <verb> <resource> [reference] [flags]\nResource commands:\n".freeze
      COMMANDS = COMMAND_MODULES.flat_map { |catalog| catalog.commands.to_a }.to_h.freeze
      USAGE = {
        "describe" => "usage: planka describe <resource> REF [flags]\n",
        "get" => "usage: planka get <resource> [REF] [flags]\n",
        "create" => "usage: planka create <resource> [flags]\n",
        "add" => "usage: planka add <resource> REF --card CARD [flags]\n",
        "remove" => "usage: planka remove <resource> REF --card CARD [flags]\n",
        "update" => "usage: planka update <resource> REF [flags]\n",
        "move" => "usage: planka move <resource> REF [flags]\n",
        "delete" => "usage: planka delete <resource> REF [flags]\n",
      }.freeze
      GROUPS = USAGE.to_h { |verb, usage| [[verb], usage + COMMAND_MODULES.filter_map { |resource| resource::GROUP_HELP[verb] }.join] }.freeze

      def self.commands = COMMANDS
      def self.groups = GROUPS
      def self.root_help = ROOT_HELP + COMMAND_MODULES.map(&:root_help).join
    end
  end
end
