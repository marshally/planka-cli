module Planka
  module Cards
    # Observes a card's labels, then sets one verified card-label relationship.
    class Labels
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      class << self
        def read(client, label, card_id:, present:, base_url:, board_id: nil)
          card, board = Scope.read(client, card_id: card_id, board_id: board_id)
          item, included = card.values_at("item", "included")
          card_id = item.fetch("id")
          raise InvalidResponse, "Invalid card relations" unless included.is_a?(Hash)
          id = Reference.resolve(board_labels(board, item.fetch("boardId")), label, resource: "label").fetch("id")
          applied = included["cardLabels"]
          unless applied.is_a?(Array) && applied.all? { |entry| entry.is_a?(Hash) && entry["cardId"] == card_id && entry["labelId"].is_a?(String) }
            raise InvalidResponse, "Invalid card label records"
          end
          exists = applied.any? { |entry| entry["labelId"] == id }
          data = { "cardId" => card_id, "labelId" => id, "present" => present }
          return MutationResult.new(data: data, changed: false) if exists == present
          mutate(client, card_id, id, present, data)
        end

        private

        def board_labels(board, board_id)
          labels = board["labels"]
          unless labels.is_a?(Array) && labels.all? { |record| record.is_a?(Hash) && Records.id?(record["id"]) &&
              record["boardId"] == board_id && (record["name"].nil? || record["name"].is_a?(String)) } &&
              labels.map { |record| record["id"] }.uniq.size == labels.size
            raise InvalidResponse, "Invalid board labels"
          end
          labels
        end

        def mutate(client, card, id, present, data)
          response = present ? client.add_card_label(card, id) : client.remove_card_label(card, id)
          item = response["item"]
          unless item.is_a?(Hash) && item["cardId"] == card && item["labelId"] == id
            raise InvalidResponse, "Invalid relationship write response"
          end
          MutationResult.new(data: data, changed: true)
        rescue *OPERATION_ERRORS => error
          uncertain = !Client.unapplied?(error)
          raise MutationFailure.new(data: data.merge("present" => uncertain ? nil : !present),
            changed: uncertain ? nil : false, uncertain: uncertain,
            recovery: { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => card }] })
        end
      end
    end
  end
end
