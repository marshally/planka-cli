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
            get task-lists --card CARD  List a card's task lists (read-only)
            get task-list TASK_LIST  Read one card task list (read-only)
          HELP
          GROUP_HELP = {
            "get" => "  task-lists --card CARD  List a card's task lists (read-only)\n  task-list TASK_LIST  Read one card task list (read-only)\n",
          }.freeze

          # get reads one task list with a reference, otherwise the card's task lists.
          def self.prepare_get(env, instance:, flags:, reference:)
            return prepare_task_list(env, instance: instance, flags: flags, reference: reference) if reference
            raise Failure.new(code: "invalid_input", status: 2, message: "get task-lists requires --card") unless flags[:card]

            Cards.prepare_scope(env, instance: instance, flags: flags).merge(name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i)
          end

          # A task-list ID finds its own card; names need --card.
          def self.prepare_task_list(env, instance:, flags:, reference:)
            return Cards.prepare_scope(env, instance: instance, flags: flags) if flags[:card]
            raise Failure.new(code: "invalid_input", status: 2, message: "Task list names require --card") unless Records.id?(reference)

            { board_id: flags[:board] && BoardScope.resolve(instance, flags[:board].first) }
          end

          def self.get(client, reference = nil, card_id: nil, board_id: nil, **collection)
            task_lists = Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id)
            reference ? task_lists.find(reference) : task_lists.all(**collection)
          end

          def self.format_task_list(task_list) = "#{task_list["name"]} (#{task_list["id"]}) on card #{task_list["cardId"]}"

          def self.format_task_lists(data)
            return format_task_list(data) if data.is_a?(Hash)

            data.empty? ? "No task lists." : data.map { |task_list| format_task_list(task_list) }.join("\n")
          end

          COMMANDS = {
            ["get", "task-list"] => Command.new(aliases: [["get", "task-lists"]], names: true, optional_reference: true, collection_read: true,
                                                resource: "task list", collection_flags: [:name, :limit],
                                                flags: { "--card CARD" => :card, "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit },
                                                validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_get),
                                                help: "", operation: method(:get), formatter: method(:format_task_lists)),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
