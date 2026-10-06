require "planka/cli/failure"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Cards
        module Members
          ROOT_HELP = <<~HELP
              get members --card CARD  List assigned users (read-only)
              get member USER --card CARD  Read one assignment (read-only)
              add member USER --card CARD  Assign an existing board user
              remove member USER --card CARD  Detach only this assignment
          HELP
          COMMON_HELP = <<~HELP
            USER is an ID, same-instance /users/ID URL, or exact display name on the card's board.
            CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
            Explicit card IDs/URLs ignore the default board; --board asserts the actual parent.
            Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
            Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
            Success exits 0, local input 2, operational failures 1.
            No workflow claim, card move, or account mutation. All resource commands preserve unrelated members.
          HELP
          GET_HELP = <<~HELP + COMMON_HELP
            usage: planka get members [USER] --card CARD [--board BOARD] [--name NAME] [--limit N] [-o human|json]
            Without USER, read the complete collection; exact --name filtering precedes a positive --limit.
            With USER, read one assignment; filters and limits are rejected.
            Results order by native membership ID. A limit reports accurate meta.complete and human truncation.
            JSON uses data/meta/error; data contains id, name, username, cardId, membershipId, createdAt, updatedAt.
            Collection data is an array with meta.complete; individual data is an object with empty meta.
          HELP
          ADD_HELP = <<~HELP + COMMON_HELP
            usage: planka add member USER --card CARD [--board BOARD] [-o human|json]
            Add an existing board user; an existing assignment is a no-op.
            JSON uses data/meta/error with identity, assignment metadata, and assigned; meta.changed is true/false/null.
            Native board editor permission is required. A lost/malformed write response gives readback-membership recovery.
          HELP
          REMOVE_HELP = <<~HELP + COMMON_HELP
            usage: planka remove member USER --card CARD [--board BOARD] [-o human|json]
            Remove only this assignment; an absent assignment is a no-op. Preserve the user and card.
            JSON uses data/meta/error with identity, assignment metadata, and assigned; meta.changed is true/false/null.
            Native board editor permission is required. A lost/malformed write response gives readback-membership recovery.
          HELP

          def self.prepare(env, instance:, flags:)
            raise Failure.new(code: "invalid_input", status: 2, message: "Exactly one --card is required") unless flags[:card]
            card = instance.resolve(flags.fetch(:card).first, resource: "card", collection: "cards", names: true)
            board = flags[:board]&.first
            if !Records.id?(card) && !board
              board = env["PLANKA_BOARD_ID"]
              if board.nil? || board.empty?
                raise Failure.new(code: "invalid_input", status: 2, message: "Card names require --board or PLANKA_BOARD_ID")
              end
              begin
                board = instance.resolve(board, resource: "board", collection: "boards")
              rescue Instance::InvalidReference
                raise Failure.new(code: "configuration_error", message: "PLANKA_BOARD_ID must be a board ID or same-instance URL")
              end
            end
            board = instance.resolve(board, resource: "board", collection: "boards") if board
            { card_id: card, board_id: board,
              name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
          end

          def self.validate(flags)
            return "Conflicting scalar flags" if flags.values.any? { |values| values.uniq.size > 1 }
            return "Flags must have nonempty values" if flags.values.any? { |values| values.first.strip.empty? }
            return "--limit must be a positive integer" if flags[:limit] && !flags[:limit].first.match?(/\A[1-9]\d*\z/)
          end

          def self.prepare_add(env, instance:, flags:)
            prepare(env, instance: instance, flags: flags).merge(operation: :add)
          end

          def self.prepare_remove(env, instance:, flags:)
            prepare(env, instance: instance, flags: flags).merge(operation: :remove)
          end

          def self.format(data)
            if data.is_a?(Hash) && data.key?("assigned")
              return "#{data['name']} (#{data['id']}) on card #{data['cardId']}\nassigned: #{data['assigned']}"
            end
            data = [data] if data.is_a?(Hash)
            text = data.empty? ? "No card members." : data.map { |member| "#{member['name']} (#{member['id']}) on card #{member['cardId']}" }.join("\n")
            text
          end

          GROUPS = { "get" => GET_HELP, "add" => ADD_HELP, "remove" => REMOVE_HELP }.freeze

          COMMANDS = {
            ["remove", "member"] => Command.new(aliases: [["remove", "members"]], names: true, mutation: true,
              resource: "user", collection: "users", flags: { "--card CARD" => :card, "--board BOARD" => :board },
              validate_flags: method(:validate), prepare: method(:prepare_remove),
              help: REMOVE_HELP, reader: Planka::Cards::Members, formatter: method(:format)),
            ["add", "member"] => Command.new(aliases: [["add", "members"]], names: true, mutation: true,
              resource: "user", collection: "users", flags: { "--card CARD" => :card, "--board BOARD" => :board },
              validate_flags: method(:validate), prepare: method(:prepare_add),
              help: ADD_HELP, reader: Planka::Cards::Members, formatter: method(:format)),
            ["get", "member"] => Command.new(aliases: [["get", "members"]], optional_reference: true, names: true,
              collection_read: true,
              resource: "user", collection: "users",
              collection_flags: [:name, :limit],
              flags: { "--card CARD" => :card, "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit }, validate_flags: method(:validate), prepare: method(:prepare),
              help: GET_HELP, reader: Planka::Cards::Members, formatter: method(:format)),
          }.freeze

          def self.commands = COMMANDS
          def self.groups = GROUPS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
