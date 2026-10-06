require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Labels
        ROOT_HELP = "  get labels [LABEL] --board BOARD  Read board labels\n  create label --board BOARD --name NAME --color COLOR  Create a new label\n  update label LABEL --board BOARD  Update supplied label fields\n  delete label LABEL --board BOARD  Delete one label with native assignment cleanup\n".freeze
        GROUP_HELP = { "delete" => "  label LABEL --board BOARD  Delete one label with native assignment cleanup\n", "update" => "  label LABEL --board BOARD  Update supplied label fields\n", "get" => "  labels [LABEL] --board BOARD  Read board labels\n", "create" => "  label --board BOARD --name NAME --color COLOR  Create a new label\n" }.freeze
        COMMON_HELP = <<~HELP
          LABEL is an ID, same-instance /labels/ID URL, or exact name within the board.
          Requires --board BOARD or PLANKA_BOARD_ID; BOARD is an ID or same-instance /boards/ID URL.
          Community v2.2.1 has no individual label GET; board scope is required even for IDs.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. Labels/label are aliases.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get labels [LABEL] [--board BOARD] [--name NAME] [--limit N] [-o human|json]
          Read-only. Collection data is an array, individual data is an object under data/meta/error.
          Exact --name filtering precedes positive --limit; order by position then ID.
          Collection meta.complete reports matching completeness, false on truncation or malformed results.
          Data fields: id, boardId, nullable name, color, position, nullable createdAt/updatedAt.
        HELP

        def self.prepare(env, instance:, flags:)
          board = flags[:board]&.first || env["PLANKA_BOARD_ID"]
          raise Failure.new(code: "configuration_error", message: "Labels require --board or PLANKA_BOARD_ID") if board.nil? || board.empty?

          { board_id: instance.resolve(board, resource: "board", collection: "boards"), name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
        rescue Instance::InvalidReference
          raise if flags[:board]

          raise Failure.new(code: "configuration_error", message: "PLANKA_BOARD_ID must be a board ID or same-instance URL")
        end

        COLORS = %w[muddy-grey autumn-leafs morning-sky antique-blue egg-yellow desert-sand dark-granite fresh-salad
                    lagoon-blue midnight-blue light-orange pumpkin-orange light-concrete sunny-grass navy-blue lilac-eyes
                    apricot-red orange-peel silver-glint bright-moss deep-ocean summer-sky berry-red light-cocoa grey-stone
                    tank-green coral-green sugar-plum pink-tulip shady-rust wet-rock wet-moss turquoise-sea lavender-fields
                    piggy-red light-mud gun-metal modern-green french-coast sweet-lilac red-burgundy pirate-gold].freeze

        CREATE_HELP = <<~HELP + COMMON_HELP + "Colors: #{COLORS.join(", ")}\n"
          usage: planka create label [--board BOARD] --name NAME --color COLOR [--position N] [-o human|json]
          Create a new label even when its exact name already exists; append by default.
          Name is nonempty, at most 128 UTF-16 units. Color is a native Planka color.
          Position is a finite nonnegative native ordering value, not a row index.
          JSON data is the resulting label object; meta.changed is true/false/null.
          Unknown writes require readback-labels using get labels --board BOARD before retrying.
        HELP

        def self.validate_values(flags)
          error = Cards.validate_scope_flags(flags)
          return error if error
          return "Name must contain at most 128 UTF-16 units" if flags[:name] && flags[:name].first.encode("UTF-16LE").bytesize / 2 > 128
          return "--color must be a native Planka label color" if flags[:color] && !COLORS.include?(flags[:color].first)

          if flags[:position]
            value = Float(flags[:position].first, exception: false)
            return "--position must be finite and nonnegative" unless value && value.finite? && value >= 0
          end
          nil
        end

        def self.validate_create(flags)
          validate_values(flags)
        end

        def self.prepare_create(env, instance:, flags:)
          unless flags[:name] && flags[:color]
            raise Failure.new(code: "invalid_input", status: 2, message: "--name and --color are required")
          end

          prepare(env, instance: instance, flags: flags).slice(:board_id).merge(
            name: flags[:name].first, color: flags[:color].first, position: flags[:position] && Float(flags[:position].first)
          )
        end

        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update label LABEL [--board BOARD] [--name NAME] [--color COLOR] [--position N] [-o human|json]
          Change supplied fields only. Empty updates fail; identical updates are no-ops.
          Name/color/position use create validation; names cannot be cleared.
          JSON data is the resulting label object; meta.changed is true/false/null.
          Unknown writes require readback-label recovery; never retry blindly.
        HELP

        def self.validate_update(flags)
          validate_values(flags)
        end

        def self.prepare_update(env, instance:, flags:)
          if (flags.keys & %i[name color position]).empty?
            raise Failure.new(code: "invalid_input", status: 2, message: "At least one of --name, --color, --position is required")
          end

          attributes = flags.slice(:name, :color).to_h { |key, values| [key.to_s, values.first] }
          attributes["position"] = Float(flags[:position].first) if flags[:position]
          prepare(env, instance: instance, flags: flags).slice(:board_id).merge(attributes: attributes.freeze)
        end

        def self.format(data)
          records = data.is_a?(Array) ? data : [data]
          return "No labels." if records.empty?

          lines = records.map { |record| "#{record["id"]}\t#{record["name"]}\t#{record["color"]}\t#{record["position"]}" }
          lines << "deleted: #{data["deleted"]}" if data.is_a?(Hash) && data.key?("deleted")
          lines.join("\n")
        end

        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete label LABEL [--board BOARD] [-o human|json]
          Delete only this label. Native Planka removes its assignments; cards and other labels remain.
          No confirmation prompt or client cleanup writes. JSON data is the label plus deleted true/false/null.
          meta.changed is true/false/null. Unknown writes require readback-label recovery before retrying.
        HELP

        def self.prepare_delete(env, instance:, flags:)
          prepare(env, instance: instance, flags: flags).slice(:board_id)
        end

        COMMANDS = {
          ["delete", "label"] => Command.new(aliases: [["delete", "labels"]], names: true, mutation: true,
                                             resource: "label", collection: "labels", flags: { "--board BOARD" => :board },
                                             validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare_delete), help: DELETE_HELP, reader: Planka::Labels::Delete, formatter: method(:format)),
          ["update", "label"] => Command.new(aliases: [["update", "labels"]], names: true, mutation: true,
                                             resource: "label", collection: "labels", flags: { "--board BOARD" => :board, "--name NAME" => :name, "--color COLOR" => :color, "--position N" => :position },
                                             validate_flags: method(:validate_update), prepare: method(:prepare_update), help: UPDATE_HELP, reader: Planka::Labels::Update, formatter: method(:format)),
          ["create", "label"] => Command.new(aliases: [["create", "labels"]], reference: false, mutation: true,
                                             resource: "label", collection: "labels", flags: { "--board BOARD" => :board, "--name NAME" => :name, "--color COLOR" => :color, "--position N" => :position },
                                             validate_flags: method(:validate_create), prepare: method(:prepare_create), help: CREATE_HELP, reader: Planka::Labels::Create, formatter: method(:format)),
          ["get", "labels"] => Command.new(aliases: [["get", "label"]], names: true, optional_reference: true, collection_read: true, collection_flags: %i[name limit],
                                           resource: "label", collection: "labels", flags: { "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit },
                                           validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare), help: GET_HELP, reader: Planka::Labels::Read, formatter: method(:format)),
        }.freeze
        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
