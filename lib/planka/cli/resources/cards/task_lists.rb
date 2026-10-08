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
            create task-list --card CARD --name NAME  Create one task list on a card
            update task-list TASK_LIST --name NAME  Rename one task list
            delete task-list TASK_LIST  Delete one task list; Planka deletes its tasks
          HELP
          COMMON_HELP = <<~HELP
            TASK_LIST is an ID, or an exact name with --card CARD; Planka has no task-list URLs. A task-list ID
            alone finds its own card; --card and --board assert the actual parents.
            CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
            Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
            Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
            Success exits 0, local input 2, operational failures 1. task-list/task-lists are aliases.
            Task-list data: id, cardId, name, position, showOnFrontOfCard, hideCompletedTasks, createdAt, updatedAt.
          HELP
          GET_HELP = <<~HELP + COMMON_HELP
            usage: planka get task-lists --card CARD [--board BOARD] [--name NAME] [--limit N] [-o human|json]
                   planka get task-list TASK_LIST [--card CARD] [--board BOARD] [-o human|json]
            Read-only. Without TASK_LIST, read every task list on CARD from one card read (no paging), ordered
            by position then ID. --card is required. An exact --name matches before a positive --limit;
            filters and limits require an omitted TASK_LIST. Collection data is an array with meta.complete,
            false when truncated or the read fails. Tasks are not embedded.
            With TASK_LIST, data is one task-list object and meta is empty.
          HELP
          CREATE_HELP = <<~HELP + COMMON_HELP
            usage: planka create task-list --card CARD [--board BOARD] --name NAME [--position N] [-o human|json]
            Create a task list on CARD even when its name exists; no workflow names are implied. Appends after
            the card's task lists unless --position gives a finite nonnegative native ordering value; Planka may
            renumber positions. Only the name and position are sent, so Planka's own defaults apply to
            showOnFrontOfCard (true) and hideCompletedTasks (false). NAME is nonempty, at most 128 characters.
            JSON data is the created task list; meta.changed is true, or null with unknown_outcome.
            An unknown or malformed write response gives readback-task-lists recovery for the card and no ID.
            Read back with planka get task-lists --card CARD before retrying; creates are never retried.
          HELP
          UPDATE_HELP = <<~HELP + COMMON_HELP
            usage: planka update task-list TASK_LIST [--card CARD] [--board BOARD] --name NAME [-o human|json]
            Rename only; --name is required, and no other field is changed. Tasks, their completion, the task
            list's identity, position, and card are preserved. An identical name is a no-op (meta.changed
            false). NAME is nonempty, at most 128 characters. Native board editor permission is required.
            JSON data is the resulting task list; meta.changed is true/false/null. A rejected write keeps the
            unchanged task list; an unknown or malformed response sets the name null with readback-task-list
            recovery. Read back with planka get task-list TASK_LIST before retrying.
          HELP
          DELETE_HELP = <<~HELP + COMMON_HELP
            usage: planka delete task-list TASK_LIST [--card CARD] [--board BOARD] [-o human|json]
            Issue one native deletion without prompts; an omitted TASK_LIST is an input error and never a bulk
            delete. Planka deletes the task list's tasks with it and keeps the card and its other task lists;
            the client deletes no task individually. Native board editor permission is required. JSON data is
            the task list with deleted true; meta.changed is true/false/null. A rejected deletion keeps the
            unchanged task list without deleted; an unknown or malformed response sets deleted null with
            readback-task-list recovery. Read back with planka get task-lists --card CARD.
          HELP
          GROUP_HELP = {
            "get" => "  task-lists --card CARD  List a card's task lists (read-only)\n  task-list TASK_LIST  Read one card task list (read-only)\n",
            "create" => "  task-list --card CARD --name NAME  Create one task list on a card\n",
            "update" => "  task-list TASK_LIST --name NAME  Rename one task list\n",
            "delete" => "  task-list TASK_LIST  Delete one task list; Planka deletes its tasks\n",
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

          def self.prepare_create(env, instance:, flags:, **)
            unless flags[:card] && flags[:name]
              raise Failure.new(code: "invalid_input", status: 2, message: "create task-list requires --card and --name")
            end

            Cards.prepare_scope(env, instance: instance, flags: flags).merge(name: flags[:name].first, position: position(flags))
          end

          def self.prepare_update(env, instance:, flags:, reference:)
            raise Failure.new(code: "invalid_input", status: 2, message: "update task-list requires --name") unless flags[:name]

            prepare_task_list(env, instance: instance, flags: flags, reference: reference).merge(name: flags[:name].first)
          end

          # Validated by validate_task_list_values before preparation.
          def self.position(flags) = flags[:position] && Float(flags[:position].first)
          private_class_method :position

          def self.validate_task_list_values(flags)
            error = ScalarFlags.error(flags)
            return error if error
            if flags[:name] && !Records.text?(flags[:name].first, Planka::Cards::TaskListRecord::NAME_LIMIT)
              return "--name must be at most #{Planka::Cards::TaskListRecord::NAME_LIMIT} characters"
            end

            position = flags[:position] && Float(flags[:position].first, exception: false)
            "--position must be finite and nonnegative" if flags[:position] && !(position && Records.position?(position))
          end

          def self.get(client, reference = nil, card_id: nil, board_id: nil, **collection)
            task_lists = Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id)
            reference ? task_lists.find(reference) : task_lists.all(**collection)
          end

          def self.create(client, card_id:, board_id: nil, **attributes)
            Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id).create(**attributes)
          end

          def self.update(client, reference, card_id: nil, board_id: nil, **attributes)
            Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id).update(reference, **attributes)
          end

          def self.delete(client, reference, card_id: nil, board_id: nil)
            Planka::Cards::TaskLists.new(client, card_id: card_id, board_id: board_id).delete(reference)
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
                                                help: GET_HELP, operation: method(:get), formatter: method(:format_task_lists)),
            ["create", "task-list"] => Command.new(aliases: [["create", "task-lists"]], reference: false, mutation: true, resource: "task list",
                                                   flags: { "--card CARD" => :card, "--board BOARD" => :board, "--name NAME" => :name, "--position N" => :position },
                                                   validate_flags: method(:validate_task_list_values), prepare: method(:prepare_create),
                                                   help: CREATE_HELP, operation: method(:create), formatter: ->(task_list) { "Created task list #{format_task_list(task_list)}" }),
            ["update", "task-list"] => Command.new(aliases: [["update", "task-lists"]], names: true, mutation: true, resource: "task list",
                                                   flags: { "--card CARD" => :card, "--board BOARD" => :board, "--name NAME" => :name },
                                                   validate_flags: method(:validate_task_list_values), prepare: method(:prepare_update),
                                                   help: UPDATE_HELP, operation: method(:update), formatter: ->(task_list) { "Updated task list #{format_task_list(task_list)}" }),
            ["delete", "task-list"] => Command.new(aliases: [["delete", "task-lists"]], names: true, mutation: true, resource: "task list",
                                                   flags: { "--card CARD" => :card, "--board BOARD" => :board }, validate_flags: ScalarFlags.method(:error),
                                                   prepare: method(:prepare_task_list), help: DELETE_HELP, operation: method(:delete),
                                                   formatter: ->(task_list) { "Deleted task list #{task_list["name"]} (#{task_list["id"]}) from card #{task_list["cardId"]}" }),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
