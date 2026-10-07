require "planka"
require "planka/cli/command"
require "planka/cli/failure"

module Planka
  module CLI
    module Resources
      module Cards
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          describe card CARD  Read card details and related data (read-only)
          get card CARD  Read one concise card (read-only)
        HELP
        COMMON_HELP = <<~HELP
          CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
          Explicit card IDs/URLs ignore the default board; --board asserts the actual parent.
          Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. card/cards are aliases.
          Card data: id, name, description, type, boardId, listId, position, createdAt, updatedAt.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get card CARD [--board BOARD] [-o human|json]
          Read-only. JSON uses data/meta/error; data is one card object and meta is empty.
        HELP
        GROUP_HELP = {
          "describe" => "  card CARD  Read card details and related data (read-only)\n",
          "get" => "  card CARD  Read one concise card (read-only)\n",
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
          { board_id: scope_board(env, instance, reference, flags[:board]&.first) }
        end

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

        def self.validate_scope_flags(flags)
          return "Conflicting scalar flags" if flags.values.any? { |values| values.uniq.size > 1 }
          return "Flags must have nonempty values" if flags.values.any? { |values| values.first.to_s.strip.empty? }
          return "--limit must be a positive integer" if flags[:limit] && !flags[:limit].first.match?(/\A[1-9]\d*\z/)
        end

        def self.get(client, reference, board_id: nil)
          Planka::Boards::Cards.new(client, board_id: board_id).find(reference)
        end

        def self.format_card(card) = "#{card["name"]} (#{card["id"]}) in list #{card["listId"]}"

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
          ["get", "card"] => Command.new(aliases: [["get", "cards"]], names: true, resource: "card", collection: "cards",
                                         flags: { "--board BOARD" => :board }, validate_flags: method(:validate_scope_flags),
                                         prepare: method(:prepare_card), help: GET_HELP, operation: method(:get), formatter: method(:format_card)),
          ["describe", "card"] => Command.new(aliases: [["describe", "cards"]], resource: "card", collection: "cards", help: HELP, operation: Planka::Cards::Detail.method(:read), formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
