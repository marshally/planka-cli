require "planka/cli/failure"
require "planka/cli/command"

module Planka
  module CLI
    # One card/label association; names resolve in the card's own board.
    class LabelRelationship
      def self.read(client, label, card:, present:, base_url:)
        response = client.card(card)
        board = response.fetch("item").fetch("boardId")
        labels = Planka::Labels.new(client)
        id = labels.resolve(board_id: board, label: label)
        applied = response.fetch("included").fetch("cardLabels")
        exists = applied.any? { |entry| entry["cardId"] == card && entry["labelId"] == id }
        changed = exists != present
        if changed
          present ? client.add_card_label(card, id) : client.remove_card_label(card, id)
        end
        Planka::MutationResult.new(data: { "cardId" => card, "labelId" => id, "present" => present }, changed: changed)
      rescue Planka::Client::UnknownOutcome, Planka::InvalidResponse
        raise Failure.new(code: "unknown_outcome", message: "Label write outcome unknown; read the card before retrying",
          meta: { "changed" => nil }, data: { "cardId" => card, "labelId" => id },
          recovery: { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => card }] })
      end
    end
  end
end

module Planka
  module CLI
    module Resources
      module CardLabels
        COMMANDS = %w[add remove].to_h do |verb|
          [[verb, "label"], Command.new(names: true, mutation: true, resource: "label", collection: "labels", reader: LabelRelationship,
            flags: { "--card CARD" => :card },
            validate_flags: ->(flags) { "Exactly one --card required" unless flags[:card]&.size == 1 },
            prepare: ->(_env, instance:, flags:) { { card: instance.resolve(flags.fetch(:card).first, resource: "card", collection: "cards"), present: verb == "add" } },
            help: "usage: planka #{verb} label LABEL --card CARD [-o human|json]\nExact board label name or ID. Requires connection credentials; no default board. Idempotent; preserves other labels. JSON data: cardId, labelId, present; meta.changed. Lost response requires readback-card-labels, never blind retry.",
            formatter: ->(data) { "Card #{data['cardId']}: label #{data['labelId']} present=#{data['present']}" })]
        end.freeze
        def self.commands = COMMANDS
        def self.groups = { "add" => "add label LABEL --card CARD", "remove" => "remove label LABEL --card CARD" }
        def self.root_help = "  add/remove label LABEL --card CARD  Set one card-label relationship\n"
      end
    end
  end
end
