require "planka"
require "planka/cli/command"
require "planka/cli/failure"
require "planka/cli/resources/board_scope"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    module Resources
      module Lists
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          get lists --board BOARD  List a board's lists of every type (read-only)
          get list LIST  Read one board list (read-only)
          create list --board BOARD --name NAME  Create one kanban list
          update list LIST  Change only supplied list fields
          delete list LIST  Delete one list; Planka moves its cards to trash
        HELP
        COMMON_HELP = <<~HELP
          LIST is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID. A list ID
          alone finds its own board for active/closed lists, while archive/trash lists need --board.
          Explicit list IDs/URLs ignore the default board; --board asserts the actual parent.
          Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. list/lists are aliases.
          List data: id, name, type, color, boardId, position, createdAt, updatedAt.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get lists --board BOARD [--name NAME] [--limit N] [-o human|json]
                 planka get list LIST [--board BOARD] [-o human|json]
          Read-only. Without LIST, read every list on BOARD from one board read (no paging): active/closed
          lists by position, then archive and trash lists, which may be unnamed. --board is required;
          PLANKA_BOARD_ID is not a collection scope. An exact --name matches before a positive --limit;
          filters and limits require an omitted LIST. Collection data is an array with meta.complete, false
          when truncated or the read fails.
          With LIST, data is one list object and meta is empty.
        HELP
        CREATE_HELP = <<~HELP + COMMON_HELP
          usage: planka create list --board BOARD --name NAME [--type active|closed] [--position N] [-o human|json]
          Create a native kanban list even when its name exists. --board is required. TYPE defaults to active;
          archive and trash are system lists and cannot be created. Appends after the board's active/closed
          lists, ignoring archive/trash, unless --position gives a finite nonnegative native ordering value;
          Planka may renumber positions. NAME is nonempty, at most 128 characters.
          JSON data is the created list; meta.changed is true, or null with unknown_outcome.
          An unknown or malformed write response gives readback-lists recovery for the board and no list ID.
          Read back with planka get lists --board BOARD before retrying; creates are never retried.
        HELP
        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update list LIST [--board BOARD] [--name NAME] [--color COLOR | --clear-color]
                                         [--position N] [--type active|closed] [-o human|json]
          Change only supplied fields; at least one is required. Omitted fields, cards, and the board are
          preserved; lists never move to another board. Identical values are a no-op (meta.changed false).
          NAME is nonempty, at most 128 characters. COLOR is one of #{Planka::Boards::ListRecord::COLORS.join(", ")};
          --clear-color sends an explicit null. --position is a finite nonnegative native ordering value that
          Planka may renumber. Archive and trash lists cannot be updated.
          Changing --type between active and closed is one write. Planka itself closes or reopens the list's
          cards and completes or reopens tasks linked to them, so blockers on those cards clear or return and
          workflow next eligibility changes. No other card or task writes are made.
          JSON data is the resulting list; meta.changed is true/false/null. A rejected write keeps the unchanged
          list; an unknown or malformed response marks changed fields null with readback-list recovery.
          Read back with planka get list LIST before retrying.
        HELP
        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete list LIST [--board BOARD] [-o human|json]
          Issue one native deletion without prompts; an omitted LIST is an input error and never a bulk delete.
          Planka moves the list's cards to the board's trash list, where get cards does not read them; they are
          not deleted, and the client makes no card writes. Archive and trash lists cannot be deleted. This
          differs from deleting a board, which removes its lists and cards. Native board editor permission is
          required. JSON data is the list with deleted true; meta.changed is true/false/null. A rejected
          deletion keeps the unchanged list without deleted; an unknown or malformed response sets deleted null
          with readback-list recovery. Read back with planka get lists --board BOARD.
        HELP
        GROUP_HELP = {
          "get" => "  lists --board BOARD  List a board's lists of every type (read-only)\n  list LIST  Read one board list (read-only)\n",
          "create" => "  list --board BOARD --name NAME  Create one kanban list\n",
          "update" => "  list LIST  Change only supplied list fields\n",
          "delete" => "  list LIST  Delete one list; Planka moves its cards to trash\n",
        }.freeze

        # get reads one list with a reference, otherwise the board's lists.
        def self.prepare_get(env, instance:, flags:, reference:)
          return prepare_list(env, instance: instance, flags: flags, reference: reference) if reference
          raise Failure.invalid_input("get lists requires --board") unless flags[:board]

          { board_id: BoardScope.resolve(instance, flags[:board].first), name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
        end

        def self.prepare_list(env, instance:, flags:, reference:)
          { board_id: BoardScope.for_reference(env, instance, reference, flags[:board]&.first, resource: "List") }
        end

        def self.prepare_create(_env, instance:, flags:, **)
          unless flags[:board] && flags[:name]
            raise Failure.invalid_input("create list requires --board and --name")
          end

          { board_id: BoardScope.resolve(instance, flags[:board].first), name: flags[:name].first,
            type: flags[:type]&.first || "active", position: position(flags) }
        end

        def self.prepare_update(env, instance:, flags:, reference:)
          fields = { name: flags[:name]&.first, color: flags[:color]&.first, position: position(flags), type: flags[:type]&.first }.compact
          fields[:color] = nil if flags[:clear_color]
          if fields.empty?
            raise Failure.invalid_input("update list requires --name, --color, --clear-color, --position, or --type")
          end

          prepare_list(env, instance: instance, flags: flags, reference: reference).merge(fields)
        end

        # Validated by validate_list_values before preparation.
        def self.position(flags) = flags[:position] && Float(flags[:position].first)
        private_class_method :position

        def self.validate_list_values(flags)
          error = ScalarFlags.error(flags)
          return error if error
          if flags[:name] && !Records.text?(flags[:name].first, Planka::Boards::ListRecord::NAME_LIMIT)
            return "--name must be at most #{Planka::Boards::ListRecord::NAME_LIMIT} characters"
          end
          return "--color and --clear-color conflict" if flags[:color] && flags[:clear_color]
          if flags[:color] && !Planka::Boards::ListRecord::COLORS.include?(flags[:color].first)
            return "--color must be one of #{Planka::Boards::ListRecord::COLORS.join(", ")}"
          end
          if flags[:type] && !Planka::Boards::ListRecord::KANBAN_TYPES.include?(flags[:type].first)
            return "--type must be #{Planka::Boards::ListRecord::KANBAN_TYPES.join(" or ")}"
          end

          position = flags[:position] && Float(flags[:position].first, exception: false)
          "--position must be finite and nonnegative" if flags[:position] && !(position && Records.position?(position))
        end

        def self.get(client, reference = nil, board_id: nil, **collection)
          lists = Planka::Boards::Lists.new(client, board_id: board_id)
          reference ? lists.find(reference) : lists.all(**collection)
        end

        def self.create(client, board_id:, **attributes) = Planka::Boards::Lists.new(client, board_id: board_id).create(**attributes)

        def self.update(client, reference, board_id: nil, **attributes)
          Planka::Boards::Lists.new(client, board_id: board_id).update(reference, **attributes)
        end

        def self.delete(client, reference, board_id: nil) = Planka::Boards::Lists.new(client, board_id: board_id).delete(reference)

        def self.format_list(list) = "#{list["name"] || "(unnamed)"} (#{list["id"]}) #{list["type"]} on board #{list["boardId"]}"

        def self.format_lists(data)
          return format_list(data) if data.is_a?(Hash)

          data.empty? ? "No lists." : data.map { |list| format_list(list) }.join("\n")
        end

        COMMANDS = {
          ["get", "list"] => Command.new(aliases: [["get", "lists"]], names: true, optional_reference: true, collection_read: true,
                                         resource: "list", collection: "lists", collection_flags: [:name, :limit],
                                         flags: { "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit },
                                         validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_get),
                                         help: GET_HELP, operation: method(:get), formatter: method(:format_lists)),
          ["create", "list"] => Command.new(aliases: [["create", "lists"]], reference: false, mutation: true, resource: "list", collection: "lists",
                                            flags: { "--board BOARD" => :board, "--name NAME" => :name, "--type TYPE" => :type, "--position N" => :position },
                                            validate_flags: method(:validate_list_values), prepare: method(:prepare_create),
                                            help: CREATE_HELP, operation: method(:create), formatter: ->(list) { "Created list #{format_list(list)}" }),
          ["update", "list"] => Command.new(aliases: [["update", "lists"]], names: true, mutation: true, resource: "list", collection: "lists",
                                            flags: { "--board BOARD" => :board, "--name NAME" => :name, "--color COLOR" => :color,
                                                     "--clear-color" => :clear_color, "--position N" => :position, "--type TYPE" => :type },
                                            validate_flags: method(:validate_list_values), prepare: method(:prepare_update),
                                            help: UPDATE_HELP, operation: method(:update), formatter: ->(list) { "Updated list #{format_list(list)}" }),
          ["delete", "list"] => Command.new(aliases: [["delete", "lists"]], names: true, mutation: true, resource: "list", collection: "lists",
                                            flags: { "--board BOARD" => :board }, validate_flags: ScalarFlags.method(:error),
                                            prepare: method(:prepare_list), help: DELETE_HELP, operation: method(:delete),
                                            formatter: ->(list) { "Deleted list #{list["name"] || "(unnamed)"} (#{list["id"]}) from board #{list["boardId"]}" }),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
