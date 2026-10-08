require "planka"
require "planka/cli/command"
require "planka/cli/resources/board_scope"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    module Resources
      module Labels
        ROOT_HELP = "  get labels [LABEL] --board BOARD  Read board labels\n  create label --board BOARD --name NAME --color COLOR  Create a new label\n  update label LABEL --board BOARD  Update supplied label fields\n  delete label LABEL --board BOARD  Delete one label with native assignment cleanup\n".freeze
        GROUP_HELP = { "delete" => "  label LABEL --board BOARD  Delete one label with native assignment cleanup\n", "update" => "  label LABEL --board BOARD  Update supplied label fields\n", "get" => "  labels [LABEL] --board BOARD  Read board labels\n", "create" => "  label --board BOARD --name NAME --color COLOR  Create a new label\n" }.freeze
        COMMON_HELP = <<~HELP
          LABEL is an ID, same-instance /labels/ID URL, or exact name within the board.
          Individual references require --board BOARD or PLANKA_BOARD_ID; BOARD is an ID or same-instance /boards/ID URL.
          Community v2.2.1 has no individual label GET; board scope is required even for IDs.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. Labels/label are aliases.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get labels [LABEL] [--board BOARD] [--name NAME] [--limit N] [-o human|json]
          Collection reads require --board explicitly; PLANKA_BOARD_ID is not a collection scope.
          Read-only. Collection data is an array, individual data is an object under data/meta/error.
          Exact --name filtering precedes positive --limit; order by position then ID.
          Collection meta.complete reports matching completeness, false on truncation or malformed results.
          Data fields: id, boardId, nullable name, color, position, nullable createdAt/updatedAt.
        HELP

        def self.prepare_get(env, instance:, flags:, reference:)
          return prepare_label(env, instance: instance, flags: flags, reference: reference) if reference
          raise Failure.invalid_input("get labels requires --board") unless flags[:board]

          { board_id: BoardScope.resolve(instance, flags[:board].first), name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
        end

        def self.prepare_label(env, instance:, flags:, **)
          board = flags[:board]&.first || env["PLANKA_BOARD_ID"]
          raise Failure.invalid_input("Labels require --board or PLANKA_BOARD_ID") if board.nil? || board.empty?

          { board_id: BoardScope.resolve(instance, board) }
        rescue Instance::InvalidReference
          raise if flags[:board]

          raise Failure.configuration("PLANKA_BOARD_ID must be a board ID or same-instance URL")
        end

        def self.get(client, reference = nil, board_id:, **collection)
          labels = Planka::Boards::Labels.new(client, board_id: board_id)
          reference ? labels.find(reference) : labels.all(**collection)
        end

        def self.validate_values(flags)
          error = ScalarFlags.error(flags)
          return error if error

          Planka::Boards::LabelRecord.name!(flags[:name].first) if flags[:name]
          Planka::Boards::LabelRecord.color!(flags[:color].first) if flags[:color]
          Planka::Boards::LabelRecord.position!(Float(flags[:position].first, exception: false)) if flags[:position]
          nil
        rescue ArgumentError => error
          error.message
        end

        def self.prepare_create(_env, instance:, flags:, **)
          unless flags[:board] && flags[:name] && flags[:color]
            raise Failure.invalid_input("create label requires --board, --name, and --color")
          end

          { board_id: BoardScope.resolve(instance, flags[:board].first), name: flags[:name].first,
            color: flags[:color].first, position: flags[:position] && Float(flags[:position].first) }
        end

        def self.prepare_update(env, instance:, flags:, **)
          fields = { name: flags[:name]&.first, color: flags[:color]&.first, position: flags[:position] && Float(flags[:position].first) }.compact
          raise Failure.invalid_input("update label requires --name, --color, or --position") if fields.empty?

          prepare_label(env, instance: instance, flags: flags).merge(fields)
        end

        def self.update(client, reference, board_id:, **attributes) = Planka::Boards::Labels.new(client, board_id: board_id).update(reference, **attributes)

        def self.delete(client, reference, board_id:) = Planka::Boards::Labels.new(client, board_id: board_id).delete(reference)

        def self.create(client, board_id:, **attributes) = Planka::Boards::Labels.new(client, board_id: board_id).create(**attributes)

        def self.format(data)
          records = data.is_a?(Array) ? data : [data]
          return "No labels." if records.empty?

          lines = records.map { |record| "#{record["id"]}\t#{record["name"]}\t#{record["color"]}\t#{record["position"]}" }
          lines << "deleted: #{data["deleted"]}" if data.is_a?(Hash) && data.key?("deleted")
          lines.join("\n")
        end

        CREATE_HELP = <<~HELP + COMMON_HELP + "Colors: #{Planka::Boards::LabelRecord::COLORS.join(", ")}\n"
          usage: planka create label --board BOARD --name NAME --color COLOR [--position N] [-o human|json]
          --board is required. Create a new label even when its exact name already exists; append by default.
          Name is nonempty, at most 128 UTF-16 units. Color is a native Planka color.
          Position is a finite nonnegative native ordering value, not a row index.
          JSON data is the resulting label object; meta.changed is true/false/null.
          Unknown writes require readback-labels using get labels --board BOARD before retrying.
        HELP

        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update label LABEL [--board BOARD] [--name NAME] [--color COLOR] [--position N] [-o human|json]
          Change supplied fields only. Empty updates fail; identical updates are no-ops.
          Name/color/position use create validation; names cannot be cleared.
          JSON data is the resulting label object; meta.changed is true/false/null.
          Unknown writes require readback-label recovery; never retry blindly.
        HELP

        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete label LABEL [--board BOARD] [-o human|json]
          Delete only this label. Native Planka removes its assignments; cards and other labels remain.
          No confirmation prompt or client cleanup writes. JSON data is the label plus deleted true on success; null on an unknown deletion.
          A rejected deletion retains the unchanged label without deleted. meta.changed is true/false/null. Unknown writes require readback-label recovery before retrying.
        HELP

        COMMANDS = {
          ["delete", "label"] => Command.new(aliases: [["delete", "labels"]], names: true, mutation: true, resource: "label", collection: "labels",
                                             flags: { "--board BOARD" => :board }, validate_flags: ScalarFlags.method(:error),
                                             prepare: method(:prepare_label), help: DELETE_HELP, operation: method(:delete), formatter: method(:format)),
          ["update", "label"] => Command.new(aliases: [["update", "labels"]], names: true, mutation: true, resource: "label", collection: "labels",
                                             flags: { "--board BOARD" => :board, "--name NAME" => :name, "--color COLOR" => :color, "--position N" => :position },
                                             validate_flags: method(:validate_values), prepare: method(:prepare_update),
                                             help: UPDATE_HELP, operation: method(:update), formatter: method(:format)),
          ["create", "label"] => Command.new(aliases: [["create", "labels"]], reference: false, mutation: true, resource: "label", collection: "labels",
                                             flags: { "--board BOARD" => :board, "--name NAME" => :name, "--color COLOR" => :color, "--position N" => :position },
                                             validate_flags: method(:validate_values), prepare: method(:prepare_create),
                                             help: CREATE_HELP, operation: method(:create), formatter: method(:format)),
          ["get", "label"] => Command.new(aliases: [["get", "labels"]], names: true, optional_reference: true, collection_read: true,
                                          resource: "label", collection: "labels", collection_flags: [:name, :limit],
                                          flags: { "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit },
                                          validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_get),
                                          help: GET_HELP, operation: method(:get), formatter: method(:format)),
        }.freeze
        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
