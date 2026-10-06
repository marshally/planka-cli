require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      # Parsing and preparation of native tasks; execution lives in core Tasks.
      module Tasks
        SCOPE_FLAGS = { "--card CARD" => :card, "--board BOARD" => :board }.freeze
        LIST_FLAG = { "--task-list TASK_LIST" => :task_list }.freeze
        FIELD_FLAGS = { "--name NAME" => :name, "--position N" => :position, "--completed [BOOL]" => :completed }.freeze
        FILTER_FLAGS = { "--name NAME" => :name, "--completed [BOOL]" => :completed, "--assignee USER" => :assignee,
                         "--linked-card CARD" => :linked_card, "--limit N" => :limit }.freeze
        COMMON_HELP = <<~HELP
          References are numeric IDs or exact names within a known parent scope; ambiguity reports candidate IDs.
          Same-instance resource URLs are accepted. IDs ignore environment-default boards; --board asserts the parent.
          Task-list collections use IDs/URLs; list names need --card on create/individual reads and use the source card on moves.
          Card names require --board or PLANKA_BOARD_ID.
          Unscoped IDs are discovered in accessible finite-list board snapshots; use --card for other known cards.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD. Help is offline.
          JSON data/meta/error: task fields are id, cardId, taskListId, name, position, isCompleted,
          assigneeUserId, linkedCardId, createdAt, updatedAt. Relationships/timestamps may be null.
          Mutations report meta.changed true/false/null; uncertain writes require readback-task before retrying.
          Success exits 0, local input 2, operational/API/partial/unknown outcomes 1. No workflow conventions apply.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get tasks [TASK] [--card CARD | --task-list TASK_LIST] [--board BOARD] [flags]
          Collections require exactly one --card or --task-list. Individual names require a parent scope.
          Exact --name, --completed true|false, --assignee USER, --linked-card CARD combine with AND before --limit N.
          Filters/limit are collection-only. Sort by task-list position/ID then task position/ID.
          Collection data is an array with meta.complete; individual data is one object. No resource writes.
        HELP
        CREATE_HELP = <<~HELP + COMMON_HELP
          usage: planka create task --task-list TASK_LIST (--name NAME | --linked-card CARD) [--card CARD] [--board BOARD] [flags]
          Ordinary names must be nonempty and at most 1024 characters. --completed true|false defaults false.
          Linked tasks derive name/completion natively and reject --completed; linked cards must share the board.
          --position N is finite/nonnegative; omitted position appends. Assignment requires a separate update.
        HELP
        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update task TASK [--card CARD] [--board BOARD] [flags]
          Changes only supplied --name, --position, --completed true|false, --assignee USER or --clear-assignee.
          Empty updates and assignment/clear conflicts are rejected. Assignees must be board members.
          Linked tasks accept position only. Already satisfied updates are no-ops. --task-list belongs to move.
          The existing completion shorthands --completed and --no-completed remain accepted on update.
        HELP
        MOVE_HELP = <<~HELP + COMMON_HELP
          usage: planka move task TASK --task-list TASK_LIST [--card CARD] [--board BOARD] [--position N]
          Move within the same card only. Append unless --position is supplied; same list without position is a no-op.
          Preserve identity, name, completion, assignee and linked card. Native ordering may adjust positions.
        HELP
        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete task TASK [--card CARD] [--board BOARD] [-o human|json]
          Delete only this task, preserving the card, task lists, linked card and unrelated tasks.
          Data is the task object with deleted true (false on rejected writes, null on uncertain writes).
        HELP
        GROUP_HELP = {
          "move" => "  task TASK --task-list TASK_LIST  Move within the same card\n",
          "delete" => "  task TASK  Delete one task\n",
          "get" => "  tasks --card CARD | --task-list TASK_LIST  Read tasks\n  task TASK  Read one task\n",
          "update" => "  task TASK [--card CARD]  Update supplied task fields\n",
          "create" => "  task --task-list TASK_LIST --name NAME | --linked-card CARD  Create a task\n",
        }.freeze
        ROOT_HELP = GROUP_HELP.map { |verb, text| text.lines.map { |line| "  #{verb} #{line.strip}\n" }.join }.join.freeze

        def self.validate_flags(flags)
          scalars = flags.reject { |key, _| key == :completed }
          error = Cards.validate_scope_flags(scalars)
          return error if error
          return "Conflicting scalar flags" if flags[:completed]&.uniq&.size.to_i > 1
          if flags[:completed] && ![nil, "true", "false"].include?(flags[:completed].first)
            return "--completed requires true or false"
          end

          if flags[:position]
            value = Float(flags[:position].first, exception: false)
            return "--position must be finite and nonnegative" unless value && value.finite? && value >= 0
          end
          return "--name must contain 1 to 1024 characters" if flags[:name] && flags[:name].first.length > 1024
        end

        def self.validate_get(reference, flags)
          scopes = [:card, :task_list].count { |key| flags[key] }
          return "Exactly one --card or --task-list is required" if !reference && scopes != 1
          return "Task names require --card or --task-list" if named?(reference) && scopes.zero?
          return "--completed requires true or false" if flags[:completed] && flags[:completed].first.nil?
        end

        def self.named?(reference) = reference && !reference.match?(%r{\A(?:\d+\z|https?://)})

        def self.prepare_scope(env, instance:, flags:)
          scope = initial_scope(env, instance, flags)
          return scope unless flags[:task_list]

          list = task_list_reference(instance, flags)
          validate_task_list_scope!(list, scope)
          task_list_scope(scope, list)
        end

        def self.prepare_get(env, instance:, flags:)
          filters = collection_filters(flags)
          assignee = user_reference(instance, flags)
          linked = linked_card_reference(instance, flags)
          scope = prepare_scope(env, instance: instance, flags: flags)
          read_options(scope, filters, assignee, linked, flags)
        end

        def self.validate_create(_reference, flags)
          return "Exactly one --task-list is required" unless flags[:task_list]
          return "Exactly one --name or --linked-card is required" unless [:name, :linked_card].count { |key| flags[key] } == 1
          return "Linked tasks reject --completed" if flags[:linked_card] && flags[:completed]
          return "--completed requires true or false" if flags[:completed] && flags[:completed].first.nil?
        end

        def self.prepare_create(env, instance:, flags:)
          attrs = create_attributes(flags)
          linked = linked_card_reference(instance, flags)
          scope = prepare_scope(env, instance: instance, flags: flags)
          creation_options(scope, attrs, linked)
        end

        def self.validate_target(reference, flags)
          return "Task names require --card" if named?(reference) && !flags[:card]
        end

        def self.validate_update(reference, flags)
          error = validate_target(reference, flags)
          return error if error
          return "Update requires at least one task field" if (flags.keys & [:name, :position, :completed, :incomplete, :assignee, :clear_assignee]).empty?
          return "--assignee and --clear-assignee are mutually exclusive" if flags[:assignee] && flags[:clear_assignee]
          return "Conflicting completion flags" if flags[:completed] && flags[:incomplete]
        end

        def self.prepare_update(env, instance:, flags:)
          attrs = update_attributes(flags)
          user = user_reference(instance, flags)
          scope = prepare_scope(env, instance: instance, flags: flags)
          update_options(scope, attrs, user)
        end

        def self.validate_move(reference, flags)
          error = validate_target(reference, flags)
          return error if error
          return "Exactly one --task-list is required" unless flags[:task_list]
        end

        def self.prepare_move(env, instance:, flags:)
          scope = prepare_scope(env, instance: instance, flags: source_flags(flags))
          destination = task_list_reference(instance, flags)
          move_options(scope, destination, position_value(flags))
        end

        def self.initial_scope(env, instance, flags)
          return Cards.prepare_scope(env, instance: instance, flags: flags) if flags[:card]

          board_scope(reference_flag(instance, flags, :board, resource: "board", collection: "boards"))
        end

        def self.board_scope(board_id) = { board_id: board_id }
        def self.task_list_scope(scope, list) = scope.merge(task_list_id: list)
        def self.source_flags(flags) = flags.reject { |key, _| key == :task_list }

        def self.validate_task_list_scope!(list, scope)
          if named?(list) && !scope[:card_id]
            raise Failure.new(code: "invalid_input", status: 2, message: "Task-list names require --card")
          end
        end

        def self.reference_flag(instance, flags, key, resource:, collection:, names: false)
          value = flags[key]&.first
          value && instance.resolve(value, resource: resource, collection: collection, names: names)
        end

        def self.task_list_reference(instance, flags)
          reference_flag(instance, flags, :task_list, resource: "task list", collection: ["task-lists", "api/task-lists"], names: true)
        end

        def self.user_reference(instance, flags)
          reference_flag(instance, flags, :assignee, resource: "user", collection: "users", names: true)
        end

        def self.linked_card_reference(instance, flags)
          reference_flag(instance, flags, :linked_card, resource: "card", collection: "cards", names: true)
        end

        def self.position_value(flags) = flags[:position] && Float(flags[:position].first)

        def self.collection_filters(flags)
          filters = {}
          filters["name"] = flags[:name].first if flags[:name]
          filters["isCompleted"] = flags[:completed].first == "true" if flags[:completed]
          filters
        end

        def self.create_attributes(flags)
          attrs = {}
          attrs["name"] = flags[:name].first if flags[:name]
          attrs["isCompleted"] = flags[:completed] ? flags[:completed].first == "true" : false if flags[:name]
          attrs["position"] = position_value(flags) if flags[:position]
          attrs
        end

        def self.update_attributes(flags)
          attrs = {}
          attrs["name"] = flags[:name].first if flags[:name]
          attrs["position"] = position_value(flags) if flags[:position]
          attrs["isCompleted"] = flags[:completed].first != "false" if flags[:completed]
          attrs["isCompleted"] = false if flags[:incomplete]
          attrs["assigneeUserId"] = nil if flags[:clear_assignee]
          attrs
        end

        def self.read_options(scope, filters, assignee, linked, flags)
          scope.merge(filters: filters, assignee: assignee, linked_card: linked, limit: flags[:limit]&.first&.to_i)
        end

        def self.creation_options(scope, attributes, linked) = scope.merge(attributes: attributes, linked_card: linked)
        def self.update_options(scope, attributes, assignee) = scope.merge(attributes: attributes, assignee: assignee)
        def self.move_options(scope, destination, position) = scope.merge(destination: destination, position: position)

        private_class_method :initial_scope, :board_scope, :task_list_scope, :source_flags, :validate_task_list_scope!,
                             :reference_flag, :task_list_reference, :user_reference, :linked_card_reference, :position_value,
                             :collection_filters, :create_attributes, :update_attributes, :read_options,
                             :creation_options, :update_options, :move_options

        def self.format(data)
          records = data.is_a?(Array) ? data : [data]
          return "No tasks." if records.empty?

          records.map do |task|
            text = "#{task["name"]} (#{task["id"]}) on card #{task["cardId"]} / task list #{task["taskListId"]}\ncompleted: #{task["isCompleted"]}"
            task.key?("deleted") ? "#{text}\ndeleted: #{task["deleted"]}" : text
          end.join("\n")
        end

        COMMANDS = {
          ["move", "task"] => Command.new(aliases: [["move", "tasks"]], names: true, mutation: true,
                                          resource: "task", collection: ["tasks", "api/tasks"], flags: SCOPE_FLAGS.merge(LIST_FLAG).merge("--position N" => :position),
                                          validate_flags: method(:validate_flags), validate_inputs: method(:validate_move), prepare: method(:prepare_move),
                                          help: MOVE_HELP, reader: Planka::Tasks::Move, formatter: method(:format)),
          ["delete", "task"] => Command.new(aliases: [["delete", "tasks"]], names: true, mutation: true,
                                            resource: "task", collection: ["tasks", "api/tasks"], flags: SCOPE_FLAGS,
                                            validate_flags: method(:validate_flags), validate_inputs: method(:validate_target), prepare: method(:prepare_scope),
                                            help: DELETE_HELP, reader: Planka::Tasks::Delete, formatter: method(:format)),
          ["update", "task"] => Command.new(aliases: [["update", "tasks"]], names: true, mutation: true,
                                            resource: "task", collection: ["tasks", "api/tasks"],
                                            flags: SCOPE_FLAGS.merge(FIELD_FLAGS).merge("--no-completed" => :incomplete, "--assignee USER" => :assignee, "--clear-assignee" => :clear_assignee),
                                            validate_flags: method(:validate_flags), validate_inputs: method(:validate_update), prepare: method(:prepare_update),
                                            help: UPDATE_HELP, reader: Planka::Tasks::Update, formatter: method(:format)),
          ["get", "task"] => Command.new(aliases: [["get", "tasks"]], optional_reference: true, names: true, collection_read: true,
                                         resource: "task", collection: ["tasks", "api/tasks"], collection_flags: FILTER_FLAGS.values,
                                         flags: SCOPE_FLAGS.merge(LIST_FLAG).merge(FILTER_FLAGS),
                                         validate_flags: method(:validate_flags), validate_inputs: method(:validate_get), prepare: method(:prepare_get),
                                         help: GET_HELP, reader: Planka::Tasks, formatter: method(:format)),
          ["create", "task"] => Command.new(aliases: [["create", "tasks"]], reference: false, mutation: true,
                                            flags: SCOPE_FLAGS.merge(LIST_FLAG).merge(FIELD_FLAGS).merge("--linked-card CARD" => :linked_card),
                                            validate_flags: method(:validate_flags), validate_inputs: method(:validate_create), prepare: method(:prepare_create),
                                            help: CREATE_HELP, reader: Planka::Tasks::Create, formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
