require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Cards
        module Tasks
          ROOT_HELP = <<~HELP.gsub(/^/, "  ")
            update task TASK --card CARD --[no-]completed  Set one ordinary task's completion
          HELP
          UPDATE_HELP = <<~HELP
            usage: planka update task TASK --card CARD [--board BOARD] --completed|--no-completed [-o human|json]
            Set only completion; an already satisfied task is a no-op. Linked tasks are refused (linked_task).
            TASK is an ID or exact task name on the card.
            CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
            Explicit card IDs/URLs ignore the default board; --board asserts the actual parent.
            Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
            Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
            Success exits 0, local input 2, operational failures 1.
            JSON uses data/meta/error with id, name, taskListId, cardId, and isCompleted; meta.changed is true/false/null.
            A lost/malformed write response gives readback-task recovery. No workflow convention is applied.
          HELP

          def self.prepare(env, instance:, flags:)
            scope = Cards.prepare_scope(env, instance: instance, flags: flags)
            unless flags[:completed]
              raise Failure.new(code: "invalid_input", status: 2, message: "Exactly one --completed or --no-completed is required")
            end

            scope.merge(completed: flags.fetch(:completed).first)
          end

          def self.format(data) = "#{data["name"]} (#{data["id"]}) on card #{data["cardId"]}\ncompleted: #{data["isCompleted"]}"

          GROUP_HELP = { "update" => "  task TASK --card CARD  Set one ordinary task's completion\n" }.freeze

          COMMANDS = {
            ["update", "task"] => Command.new(aliases: [["update", "tasks"]], names: true, mutation: true,
                                              resource: "task", collection: "tasks", flags: { "--card CARD" => :card, "--board BOARD" => :board, "--[no-]completed" => :completed },
                                              validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare),
                                              help: UPDATE_HELP, reader: Planka::Cards::Tasks, formatter: method(:format)),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
