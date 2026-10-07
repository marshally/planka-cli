require "planka"
require "planka/cli/command"
require "planka/cli/failure"

module Planka
  module CLI
    module Resources
      module Cards
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          describe card CARD  Read card details and related data (read-only)
          get cards --board BOARD|--list LIST  List cards with exact filters (read-only)
          get card CARD  Read one concise card (read-only)
          create card --list LIST --name NAME  Create one native card
          update card CARD  Change only supplied card fields
          move card CARD --list LIST  Move a card to a list on its board
        HELP
        COMMON_HELP = <<~HELP
          CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
          Explicit card IDs/URLs ignore the default board; --board asserts the actual parent.
          Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. card/cards are aliases.
          Card data: id, name, description, type, boardId, listId, position, createdAt, updatedAt.
        HELP
        LIST_HELP = <<~HELP
          LIST is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID; a list ID
          alone finds its own board for active/closed lists, while archive/trash lists need --board.
        HELP
        GET_HELP = <<~HELP + LIST_HELP + COMMON_HELP
          usage: planka get cards (--board BOARD | --list LIST [--board BOARD]) [--name NAME]
                                  [--label LABEL]... [--member USER]... [--limit N] [-o human|json]
                 planka get card CARD [--board BOARD] [-o human|json]
          Read-only. Without CARD, read the complete board or list collection: active/closed lists in board
          order by card position, then archive/trash lists paged newest list change first.
          Exact --name, every --label (board label ID/name), and every --member (board user ID/name) must
          all match before a positive --limit; filters and limits require an omitted CARD.
          Collection data is an array with meta.complete, false when truncated or a page fails; failures keep
          matching cards read so far. Pages are not a consistent snapshot of concurrent changes.
          With CARD, data is one card object and meta is empty; card names resolve on active/closed lists.
        HELP
        CREATE_HELP = <<~HELP + LIST_HELP + COMMON_HELP
          usage: planka create card --list LIST [--board BOARD] --name NAME [--description-file FILE|-]
                                    [--position N] [-o human|json]
          Create a native card even when its name exists; no criteria, claims, blockers, or members.
          Uses the board's default card type. Appends to an active/closed list unless --position gives a
          finite nonnegative native ordering value; archive/trash lists take no position.
          NAME is nonempty, at most 1024 characters. A description file (- for stdin) must be nonempty,
          at most 1048576 characters; it is read before any request.
          JSON data is the created card; meta.changed is true, or null with unknown_outcome.
          An unknown or malformed write response gives readback-cards recovery for the list and no card ID.
          Read back with planka get cards --list LIST before retrying; creates are never retried.
        HELP
        GROUP_HELP = {
          "describe" => "  card CARD  Read card details and related data (read-only)\n",
          "get" => "  cards --board BOARD|--list LIST  List cards with exact filters (read-only)\n  card CARD  Read one concise card (read-only)\n",
          "create" => "  card --list LIST --name NAME  Create one native card\n",
          "update" => "  card CARD  Change only supplied card fields\n",
          "move" => "  card CARD --list LIST  Move a card to a list on its board\n",
        }.freeze
        HELP = <<~HELP
          usage: planka describe card CARD [--output human|json]
          Read-only: card ID or same-instance card URL; no board setting required.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
          Example: planka describe card 123 -o json
        HELP

        # Card scope shared by card-scoped resource commands: --card is an ID, URL,
        # or exact name within --board BOARD or PLANKA_BOARD_ID.
        def self.prepare_scope(env, instance:, flags:, **)
          raise Failure.new(code: "invalid_input", status: 2, message: "Exactly one --card is required") unless flags[:card]

          card = instance.resolve(flags.fetch(:card).first, resource: "card", collection: "cards", names: true)
          { card_id: card, board_id: scope_board(env, instance, card, flags[:board]&.first) }
        end

        def self.prepare_card(env, instance:, flags:, reference:)
          return { board_id: scope_board(env, instance, reference, flags[:board]&.first) } if reference

          prepare_collection(env, instance, flags)
        end

        def self.prepare_collection(env, instance, flags)
          raise Failure.new(code: "invalid_input", status: 2, message: "get cards requires --board or --list") unless flags[:board] || flags[:list]

          list_scope(env, instance, flags).merge(name: flags[:name]&.first, labels: flags.fetch(:labels, []),
                                                 members: flags.fetch(:members, []), limit: flags[:limit]&.first&.to_i)
        end

        def self.prepare_create(env, instance:, flags:, **)
          unless flags[:list] && flags[:name]
            raise Failure.new(code: "invalid_input", status: 2, message: "create card requires --list and --name")
          end

          list_scope(env, instance, flags).merge(name: flags[:name].first, description: description(flags),
                                                 position: flags[:position] && Float(flags[:position].first))
        end

        # An explicit --board asserts the list's parent; list names fall back to
        # PLANKA_BOARD_ID; list IDs and URLs find their own board.
        def self.list_scope(env, instance, flags)
          board = flags[:board]&.first
          list = flags[:list] && instance.resolve(flags[:list].first, resource: "list", collection: "lists", names: true)
          board_id = if board then instance.resolve(board, resource: "board", collection: "boards")
                     elsif list && !Records.id?(list) then default_board(env, instance)
                     end
          { board_id: board_id, list: list }
        end

        def self.description(flags)
          path = flags[:description_file]&.first or return
          text = path == "-" ? $stdin.read : File.read(path)
          return text if Planka::Boards::Cards.text?(text, Planka::Boards::Cards::DESCRIPTION_LIMIT)

          raise Failure.new(code: "invalid_input", status: 2, message: "--description-file must be nonempty and at most 1048576 characters")
        rescue SystemCallError, IOError, EncodingError
          raise Failure.new(code: "invalid_input", status: 2, message: "Could not read --description-file")
        end

        def self.prepare_update(env, instance:, flags:, reference:)
          unless flags[:name] || flags[:description_file]
            raise Failure.new(code: "invalid_input", status: 2, message: "update card requires --name or --description-file")
          end

          prepare_card(env, instance: instance, flags: flags, reference: reference)
            .merge(name: flags[:name]&.first, description: description(flags))
        end

        def self.prepare_move(env, instance:, flags:, reference:)
          raise Failure.new(code: "invalid_input", status: 2, message: "move card requires --list") unless flags[:list]

          prepare_card(env, instance: instance, flags: flags, reference: reference)
            .merge(list: instance.resolve(flags[:list].first, resource: "list", collection: "lists", names: true),
                   position: flags[:position] && Float(flags[:position].first))
        end
        private_class_method :prepare_collection, :list_scope, :description

        # An explicit --board always asserts the parent; card names fall back to
        # PLANKA_BOARD_ID; IDs and URLs need no board.
        def self.scope_board(env, instance, card, explicit)
          return instance.resolve(explicit, resource: "board", collection: "boards") if explicit

          default_board(env, instance) unless Records.id?(card)
        end

        def self.default_board(env, instance)
          board = env["PLANKA_BOARD_ID"]
          if board.nil? || board.empty?
            raise Failure.new(code: "invalid_input", status: 2, message: "Card names require --board or PLANKA_BOARD_ID")
          end

          instance.resolve(board, resource: "board", collection: "boards")
        rescue Instance::InvalidReference
          raise Failure.new(code: "configuration_error", message: "PLANKA_BOARD_ID must be a board ID or same-instance URL")
        end
        private_class_method :scope_board, :default_board

        def self.validate_card_values(flags)
          error = validate_scope_flags(flags)
          return error if error
          if flags[:name] && !Planka::Boards::Cards.text?(flags[:name].first, Planka::Boards::Cards::NAME_LIMIT)
            return "--name must be at most 1024 characters"
          end

          position = flags[:position] && Float(flags[:position].first, exception: false)
          "--position must be finite and nonnegative" if flags[:position] && !(position&.finite? && position >= 0)
        end

        def self.validate_collection_flags(flags)
          repeated = flags.slice(:labels, :members)
          return "Flags must have nonempty values" if repeated.values.flatten.any? { |value| value.strip.empty? }

          validate_scope_flags(flags.except(:labels, :members))
        end

        def self.validate_scope_flags(flags)
          return "Conflicting scalar flags" if flags.values.any? { |values| values.uniq.size > 1 }
          return "Flags must have nonempty values" if flags.values.any? { |values| values.first.to_s.strip.empty? }
          return "--limit must be a positive integer" if flags[:limit] && !flags[:limit].first.match?(/\A[1-9]\d*\z/)
        end

        def self.get(client, reference = nil, board_id: nil, **collection)
          cards = Planka::Boards::Cards.new(client, board_id: board_id)
          reference ? cards.find(reference) : cards.all(**collection)
        end

        def self.create(client, list:, board_id: nil, **attributes)
          Planka::Boards::Cards.new(client, board_id: board_id).create(list, **attributes)
        end

        def self.update(client, reference, board_id: nil, **attributes)
          Planka::Boards::Cards.new(client, board_id: board_id).update(reference, **attributes)
        end

        def self.move(client, reference, board_id: nil, **destination)
          Planka::Boards::Cards.new(client, board_id: board_id).move(reference, **destination)
        end

        def self.format_card(card) = "#{card["name"]} (#{card["id"]}) in list #{card["listId"]}"

        def self.format_cards(data)
          return format_card(data) if data.is_a?(Hash)

          data.empty? ? "No cards." : data.map { |card| format_card(card) }.join("\n")
        end

        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update card CARD [--board BOARD] [--name NAME] [--description-file FILE|-] [-o human|json]
          Change only supplied fields; at least one is required. Omitted fields, list, position, labels,
          members, tasks, and comments are preserved. Identical values are a no-op (meta.changed false).
          NAME is nonempty, at most 1024 characters. A description file (- for stdin) must be nonempty and at
          most 1048576 characters; empty input is rejected, and clearing a description is not supported.
          JSON data is the resulting card; meta.changed is true/false/null. A rejected write keeps the unchanged
          card; an unknown or malformed response marks requested fields null with readback-card recovery.
        HELP

        MOVE_HELP = <<~HELP + COMMON_HELP
          usage: planka move card CARD --list LIST [--board BOARD] [--position N] [-o human|json]
          Move to LIST on the card's own board, appending to an active/closed list unless --position gives a
          finite nonnegative native ordering value; archive/trash lists take no position. LIST is an ID,
          same-instance URL, or exact name on the card's board. The current list without --position is a
          no-op. Only list and position change: members, labels, tasks, and comments are preserved, and moving
          neither claims nor releases work. JSON data is the resulting card; meta.changed is true/false/null.
          A rejected write keeps the unchanged card; an unknown or malformed response marks the list and
          position null with readback-card recovery. Read back with planka get card CARD before retrying.
        HELP

        def self.format(detail)
          lines = [
            "#{detail.fetch("name")} (#{detail.fetch("url")})",
            "List: #{detail.fetch("listName")}",
            "Labels: #{Array(detail["labels"]).map { |label| label["name"] }.join(", ").then { |names| names.empty? ? "none" : names }}",
          ]
          description = detail["description"]
          lines.concat(["", "Description:", description]) if description && !description.empty?
          members = Array(detail["members"])
          lines.concat(["", "Members:", *members.map { |member| "- #{member}" }]) unless members.empty?
          task_lists = Array(detail["taskLists"])
          unless task_lists.empty?
            lines.concat(["", "Tasks:"])
            task_lists.each do |list|
              lines << "#{list["name"]}:"
              lines.concat(Array(list["tasks"]).map { |task| "  [#{task["isCompleted"] ? "x" : " "}] #{task["name"]}" })
            end
          end
          blockers = Array(detail["blockers"])
          unless blockers.empty?
            lines.concat(["", "Blockers:", *blockers.map { |blocker| "- #{blocker["cardId"]} (#{blocker["completed"] ? "closed" : "open"})" }])
          end
          comments = Array(detail["comments"])
          unless comments.empty?
            lines.concat(["", "Comments:", *comments.map { |comment| "- #{comment["text"]}" }])
          end
          lines.join("\n")
        end

        COMMANDS = {
          ["get", "card"] => Command.new(aliases: [["get", "cards"]], names: true, optional_reference: true, collection_read: true,
                                         resource: "card", collection: "cards", collection_flags: [:list, :name, :labels, :members, :limit],
                                         flags: { "--board BOARD" => :board, "--list LIST" => :list, "--name NAME" => :name,
                                                  "--label LABEL" => :labels, "--member USER" => :members, "--limit N" => :limit },
                                         validate_flags: method(:validate_collection_flags), prepare: method(:prepare_card),
                                         help: GET_HELP, operation: method(:get), formatter: method(:format_cards)),
          ["create", "card"] => Command.new(aliases: [["create", "cards"]], reference: false, mutation: true, resource: "card", collection: "cards",
                                            flags: { "--list LIST" => :list, "--board BOARD" => :board, "--name NAME" => :name,
                                                     "--description-file FILE" => :description_file, "--position N" => :position },
                                            validate_flags: method(:validate_card_values), prepare: method(:prepare_create),
                                            help: CREATE_HELP, operation: method(:create), formatter: ->(card) { "Created card #{format_card(card)}" }),
          ["update", "card"] => Command.new(aliases: [["update", "cards"]], names: true, mutation: true, resource: "card", collection: "cards",
                                            flags: { "--board BOARD" => :board, "--name NAME" => :name, "--description-file FILE" => :description_file },
                                            validate_flags: method(:validate_card_values), prepare: method(:prepare_update),
                                            help: UPDATE_HELP, operation: method(:update), formatter: ->(card) { "Updated card #{format_card(card)}" }),
          ["move", "card"] => Command.new(aliases: [["move", "cards"]], names: true, mutation: true, resource: "card", collection: "cards",
                                          flags: { "--list LIST" => :list, "--board BOARD" => :board, "--position N" => :position },
                                          validate_flags: method(:validate_card_values), prepare: method(:prepare_move),
                                          help: MOVE_HELP, operation: method(:move), formatter: ->(card) { "Moved card #{format_card(card)}" }),
          ["describe", "card"] => Command.new(aliases: [["describe", "cards"]], resource: "card", collection: "cards", help: HELP, operation: Planka::Cards::Detail.method(:read), formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
