require "planka"
require "planka/cli/command"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    module Resources
      module Boards
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          describe board BOARD  Read board snapshot and related data (read-only)
          get boards --project PROJECT  List visible project boards (read-only)
          get board BOARD  Read one concise board (read-only)
          create board --project PROJECT --name NAME  Create one board
          update board BOARD  Change supplied name/position
          delete board BOARD  Delete one board and its native contents
        HELP
        GROUP_HELP = {
          "describe" => "  board BOARD  Read board snapshot and related data (read-only)\n",
          "get" => "  boards --project PROJECT  List visible project boards (read-only)\n  board BOARD  Read one concise board (read-only)\n",
          "create" => "  board --project PROJECT --name NAME  Create one board\n",
          "update" => "  board BOARD  Change supplied name/position\n",
          "delete" => "  board BOARD  Delete one board and its native contents\n",
        }.freeze
        HELP = <<~HELP
          usage: planka describe board BOARD [--output human|json]
          Read-only: board ID or same-instance board URL; an explicit target is required.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Human output matches snapshot. JSON uses data/meta/error; failures exit 1 or 2.
          Example: planka describe board 123 -o json
        HELP
        COMMON_HELP = <<~HELP
          BOARD is an ID, same-instance /boards/ID URL, or exact name with --project PROJECT.
          PROJECT is an ID or same-instance /projects/ID URL; project names are not accepted.
          --project asserts the board's parent, never relocates it. PLANKA_BOARD_ID is not used.
          Missing/ambiguous names fail; ambiguity reports candidate IDs. board/boards are aliases.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Board data: id, projectId, name, position, createdAt, updatedAt, url.
          JSON uses data/meta/error. Default human output shows name, ID, project ID, and URL.
          Success exits 0, local input 2, operational/API failures 1. Reads use native visibility;
          create/update/delete require project-manager permission (including native owner rules).
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get boards --project PROJECT [--name NAME] [--limit N] [-o human|json]
                 planka get board BOARD [--project PROJECT] [-o human|json]
          Read-only. Collection scope must be explicit. One project read supplies all visible boards
          without paging, sorted by position then numeric ID. Exact --name filtering precedes positive
          --limit. Filters/limit require an omitted BOARD; label/member filters are unsupported.
          Collection data is an array; meta.complete is false for truncation or failed retrieval.
          Failed reads retain validated matching records and exit 1. Individual data is an object
          with empty meta. Human collections show one board per line or No boards., with a truncation notice.
          Example: planka get boards --project 123 --limit 10 -o json
        HELP
        CREATE_HELP = <<~HELP + COMMON_HELP
          usage: planka create board --project PROJECT --name NAME [--position N] [-o human|json]
          Always create, including when the name exists. NAME must be nonblank, at most 128 UTF-16 units.
          Append at the highest project position plus 65536 (65536 in an empty project), unless --position
          supplies a finite nonnegative ordering value. Planka may normalize positions and renumber boards.
          Native creation gives the creator editor membership and creates archive and trash lists;
          no extra client membership/list writes are made. Imports and display settings are not supported.
          Human output starts Created board. JSON data is the resulting board; meta.changed is true.
          Rejected writes keep an uncreated placeholder and changed false. Unknown writes have changed null;
          retain a new returned ID when available, otherwise no ID is invented. Use readback-boards for
          the project, or readback-board with a returned board ID. Creates are never blindly retried.
          Read back with planka get boards --project PROJECT before reconciling an uncertain create.
          Example: planka create board --project 123 --name Delivery -o json
        HELP
        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update board BOARD [--project PROJECT] [--name NAME] [--position N] [-o human|json]
          Supply a nonblank name (at most 128 UTF-16 units), a finite nonnegative position, or both.
          Only supplied changed fields are sent; omitted fields remain unchanged, including project.
          Identical values are a no-op. Positions may be normalized by Planka. Neither field can be cleared.
          Human output starts Updated board. JSON data is the resulting board; meta.changed is true/false/null.
          Rejection keeps the observed board. Unknown/malformed writes mark requested changed fields null
          and give readback-board recovery. Read with planka get board BOARD before retrying.
          Example: planka update board 456 --name Delivery -o json
        HELP
        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete board BOARD [--project PROJECT] [-o human|json]
          Send one target deletion without prompts. Planka removes its lists, cards, labels, and memberships
          and related data on the server. The client never traverses/deletes children. No --yes or --cascade.
          Human output starts Deleted board. JSON data is the observed board plus deleted true;
          meta.changed is true/false/null. Rejection preserves the board without deleted; unknown/malformed
          responses set deleted null and give readback-board recovery. Read back with planka get board BOARD
          or planka get boards --project PROJECT. No automatic retries or implied bulk deletion.
          Example: planka delete board 456 -o json
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

        def self.prepare_get(env, instance:, flags:, reference:)
          return prepare_board(env, instance: instance, flags: flags, reference: reference) if reference
          raise Failure.invalid_input("get boards requires --project") unless flags[:project]

          prepare_board(env, instance: instance, flags: flags, reference: nil).merge(name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i)
        end

        def self.prepare_board(_env, instance:, flags:, reference:)
          if reference && !Records.id?(reference) && !flags[:project]
            raise Failure.invalid_input("Board names require --project")
          end

          { project_id: flags[:project] && instance.resolve(flags[:project].first, resource: "project", collection: "projects"), base_url: instance.base_url }
        rescue Instance::InvalidReference => error
          raise Failure.invalid_input(error.message)
        end

        def self.get(client, reference = nil, name: nil, limit: nil, **options)
          boards = Planka::Projects::Boards.new(client, **options)
          reference ? boards.find(reference) : boards.all(name: name, limit: limit)
        end

        def self.prepare_create(env, instance:, flags:, **)
          raise Failure.invalid_input("create board requires --project and --name") unless flags[:project] && flags[:name]

          prepare_board(env, instance: instance, flags: flags, reference: nil).merge(name: flags[:name].first,
                                                                                     position: flags[:position] && Float(flags[:position].first))
        end

        def self.validate_values(flags)
          error = ScalarFlags.error(flags)
          return error if error
          if flags[:name] && !Records.text?(flags[:name].first, Planka::Projects::BoardRecord::NAME_LIMIT)
            return "--name must be nonempty and at most 128 UTF-16 units"
          end

          position = flags[:position] && Float(flags[:position].first, exception: false)
          "--position must be finite and nonnegative" if flags[:position] && !(position && Records.position?(position))
        end

        def self.create(client, base_url:, project_id:, **attributes)
          Planka::Projects::Boards.new(client, base_url: base_url, project_id: project_id).create(**attributes)
        end

        def self.prepare_update(env, instance:, flags:, reference:)
          fields = { name: flags[:name]&.first, position: flags[:position] && Float(flags[:position].first) }.compact
          raise Failure.invalid_input("update board requires --name or --position") if fields.empty?

          prepare_board(env, instance: instance, flags: flags, reference: reference).merge(fields)
        end

        def self.update(client, reference, base_url:, project_id:, **attributes)
          Planka::Projects::Boards.new(client, base_url: base_url, project_id: project_id).update(reference, **attributes)
        end

        def self.delete(client, reference, **options) = Planka::Projects::Boards.new(client, **options).delete(reference)

        def self.format_board(board) = "#{board["name"]} (#{board["id"]}) on project #{board["projectId"]}: #{board["url"]}"

        def self.format_boards(boards)
          return format_board(boards) if boards.is_a?(Hash)

          boards.empty? ? "No boards." : boards.map { |board| format_board(board) }.join("\n")
        end

        COMMANDS = {
          ["delete", "board"] => Command.new(aliases: [["delete", "boards"]], names: true, mutation: true,
                                             resource: "board", collection: "boards", flags: { "--project PROJECT" => :project },
                                             validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_board),
                                             help: DELETE_HELP, operation: method(:delete),
                                             formatter: ->(board) { "Deleted board #{format_board(board)}" }),
          ["update", "board"] => Command.new(aliases: [["update", "boards"]], names: true, mutation: true,
                                             resource: "board", collection: "boards",
                                             flags: { "--project PROJECT" => :project, "--name NAME" => :name, "--position N" => :position },
                                             validate_flags: method(:validate_values), prepare: method(:prepare_update),
                                             help: UPDATE_HELP, operation: method(:update),
                                             formatter: ->(board) { "Updated board #{format_board(board)}" }),
          ["create", "board"] => Command.new(aliases: [["create", "boards"]], reference: false, mutation: true,
                                             resource: "board", collection: "boards",
                                             flags: { "--project PROJECT" => :project, "--name NAME" => :name, "--position N" => :position },
                                             validate_flags: method(:validate_values), prepare: method(:prepare_create),
                                             help: CREATE_HELP, operation: method(:create),
                                             formatter: ->(board) { "Created board #{format_board(board)}" }),
          ["get", "board"] => Command.new(aliases: [["get", "boards"]], names: true, optional_reference: true, collection_read: true,
                                          resource: "board", collection: "boards", collection_flags: [:name, :limit],
                                          flags: { "--project PROJECT" => :project, "--name NAME" => :name, "--limit N" => :limit },
                                          validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_get),
                                          help: GET_HELP, operation: method(:get), formatter: method(:format_boards)),
          ["describe", "board"] => Command.new(aliases: [["describe", "boards"]], resource: "board", collection: "boards", help: HELP, operation: Planka::Boards::Snapshot.method(:read), formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
