require "planka"
require "planka/cli/command"
require "planka/cli/failure"
require "planka/cli/card_input"
require "planka/cli/resources/scalar_flags"

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
          delete card CARD  Delete one card with native cleanup
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
          Read-only. Without CARD, read the cards in the board's active/closed lists, in board list order
          by card position, or in one such list. Archive/trash cards are not read; such a LIST is rejected.
          Exact --name, every --label (board label ID/name), and every --member (board user ID/name) must
          all match before a positive --limit; filters and limits require an omitted CARD.
          Collection data is an array with meta.complete, false when truncated or the read fails; failures
          keep matching cards read so far.
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
          An unknown or malformed write response keeps a valid new returned ID for readback-card recovery;
          otherwise it gives readback-cards recovery for the list without inventing an ID.
          Read back with planka get cards --list LIST before retrying; creates are never retried.
        HELP
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
        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete card CARD [--board BOARD] [-o human|json]
          Issue one native deletion without prompts; an omitted CARD is an input error and never a bulk delete.
          Planka deletes the card's task lists, tasks, attachments, comments, memberships, label assignments,
          and subscriptions, and clears links to it from other cards' tasks without deleting those cards.
          Native board editor permission is required. JSON data is the card with deleted true; meta.changed is
          true/false/null. A rejected deletion keeps the unchanged card without deleted; an unknown or malformed
          response sets deleted null with readback-card recovery. Read back with planka get card CARD.
        HELP
        GROUP_HELP = {
          "describe" => "  card CARD  Read card details and related data (read-only)\n",
          "get" => "  cards --board BOARD|--list LIST  List cards with exact filters (read-only)\n  card CARD  Read one concise card (read-only)\n",
          "create" => "  card --list LIST --name NAME  Create one native card\n",
          "update" => "  card CARD  Change only supplied card fields\n",
          "move" => "  card CARD --list LIST  Move a card to a list on its board\n",
          "delete" => "  card CARD  Delete one card with native cleanup\n",
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
          raise Failure.invalid_input("Exactly one --card is required") unless flags[:card]

          CardInput.parent(env, instance: instance, flags: flags)
        end

        # get reads one card with a reference, otherwise a scoped collection.
        def self.prepare_get(env, instance:, flags:, reference:)
          reference ? prepare_card(env, instance: instance, flags: flags, reference: reference) : prepare_collection(env, instance, flags)
        end

        def self.prepare_card(env, instance:, flags:, reference:)
          CardInput.card(env, instance: instance, flags: flags, reference: reference)
        end

        def self.prepare_collection(env, instance, flags)
          raise Failure.invalid_input("get cards requires --board or --list") unless flags[:board] || flags[:list]

          CardInput.collection(env, instance: instance, flags: flags)
        end

        def self.prepare_create(env, instance:, flags:, **)
          unless flags[:list] && flags[:name]
            raise Failure.invalid_input("create card requires --list and --name")
          end

          CardInput.creation(env, instance: instance, flags: flags)
        end

        def self.prepare_update(env, instance:, flags:, reference:)
          unless flags[:name] || flags[:description_file]
            raise Failure.invalid_input("update card requires --name or --description-file")
          end

          CardInput.update(env, instance: instance, flags: flags, reference: reference)
        end

        def self.prepare_move(env, instance:, flags:, reference:)
          raise Failure.invalid_input("move card requires --list") unless flags[:list]

          CardInput.move(env, instance: instance, flags: flags, reference: reference)
        end
        private_class_method :prepare_collection

        def self.validate_collection_flags(flags)
          repeated = flags.slice(:labels, :members)
          return "Flags must have nonempty values" if repeated.values.flatten.any? { |value| value.strip.empty? }

          validate_scope_flags(flags.except(:labels, :members))
        end

        # The flag checks shared by cards and card-scoped commands.
        def self.validate_scope_flags(flags) = ScalarFlags.error(flags)

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

        def self.delete(client, reference, board_id: nil)
          Planka::Boards::Cards.new(client, board_id: board_id).delete(reference)
        end

        def self.format_card(card) = "#{card["name"]} (#{card["id"]}) in list #{card["listId"]}"

        def self.format_cards(data)
          return format_card(data) if data.is_a?(Hash)

          data.empty? ? "No cards." : data.map { |card| format_card(card) }.join("\n")
        end

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
                                         validate_flags: method(:validate_collection_flags), prepare: method(:prepare_get),
                                         help: GET_HELP, operation: method(:get), formatter: method(:format_cards)),
          ["create", "card"] => Command.new(aliases: [["create", "cards"]], reference: false, mutation: true, resource: "card", collection: "cards",
                                            flags: { "--list LIST" => :list, "--board BOARD" => :board, "--name NAME" => :name,
                                                     "--description-file FILE" => :description_file, "--position N" => :position },
                                            validate_flags: CardInput.method(:error), prepare: method(:prepare_create),
                                            help: CREATE_HELP, operation: method(:create), formatter: ->(card) { "Created card #{format_card(card)}" }),
          ["update", "card"] => Command.new(aliases: [["update", "cards"]], names: true, mutation: true, resource: "card", collection: "cards",
                                            flags: { "--board BOARD" => :board, "--name NAME" => :name, "--description-file FILE" => :description_file },
                                            validate_flags: CardInput.method(:error), prepare: method(:prepare_update),
                                            help: UPDATE_HELP, operation: method(:update), formatter: ->(card) { "Updated card #{format_card(card)}" }),
          ["move", "card"] => Command.new(aliases: [["move", "cards"]], names: true, mutation: true, resource: "card", collection: "cards",
                                          flags: { "--list LIST" => :list, "--board BOARD" => :board, "--position N" => :position },
                                          validate_flags: CardInput.method(:error), prepare: method(:prepare_move),
                                          help: MOVE_HELP, operation: method(:move), formatter: ->(card) { "Moved card #{format_card(card)}" }),
          ["delete", "card"] => Command.new(aliases: [["delete", "cards"]], names: true, mutation: true, resource: "card", collection: "cards",
                                            flags: { "--board BOARD" => :board }, validate_flags: method(:validate_scope_flags),
                                            prepare: method(:prepare_card), help: DELETE_HELP, operation: method(:delete),
                                            formatter: ->(card) { "Deleted card #{card["name"]} (#{card["id"]}) from list #{card["listId"]}" }),
          ["describe", "card"] => Command.new(aliases: [["describe", "cards"]], resource: "card", collection: "cards", help: HELP, operation: Planka::Cards::Detail.method(:read), formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
