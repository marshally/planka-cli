require "planka"
require "planka/cli/command"
require "planka/cli/failure"
require "planka/cli/resources/board_scope"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    module Resources
      module Cards
        module TaskLists
          ROOT_HELP = <<~HELP.gsub(/^/, "  ")
            get task-list TASK_LIST  Read one card task list (read-only)
          HELP
          GROUP_HELP = {
            "get" => "  task-list TASK_LIST  Read one card task list (read-only)\n",
          }.freeze

          # A task-list ID finds its own card; names need --card.
          def self.prepare_task_list(env, instance:, flags:, reference:)
            return Cards.prepare_scope(env, instance: instance, flags: flags) if flags[:card]
            raise Failure.new(code: "invalid_input", status: 2, message: "Task list names require --card") unless Records.id?(reference)

            { board_id: flags[:board] && BoardScope.resolve(instance, flags[:board].first) }
          end

          def self.get(client, reference, card_id: nil, board_id: nil)
            Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id).find(reference)
          end

          def self.format_task_list(task_list) = "#{task_list["name"]} (#{task_list["id"]}) on card #{task_list["cardId"]}"

          COMMANDS = {
            ["get", "task-list"] => Command.new(aliases: [["get", "task-lists"]], names: true, resource: "task list",
                                                flags: { "--card CARD" => :card, "--board BOARD" => :board },
                                                validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_task_list),
                                                help: "", operation: method(:get), formatter: method(:format_task_list)),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
