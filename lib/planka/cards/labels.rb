module Planka
  module Cards
    # One association; resolution belongs to the card's own board.
    class Labels
      def self.read(client, label, card:, present:, base_url:)
        response = client.card(card)
        item, included = response.values_at("item", "included")
        unless item.is_a?(Hash) && item["id"] == card && item["boardId"].is_a?(String) && included.is_a?(Hash)
          raise InvalidResponse, "Invalid label card"
        end
        id = Planka::Labels.new(client).resolve(board_id: item["boardId"], label: label)
        applied = included["cardLabels"]
        unless applied.is_a?(Array) && applied.all? { |entry| entry.is_a?(Hash) && entry["cardId"] == card && entry["labelId"].is_a?(String) }
          raise InvalidResponse, "Invalid card label records"
        end
        exists = applied.any? { |entry| entry["labelId"] == id }
        data = { "cardId" => card, "labelId" => id, "present" => present }
        return MutationResult.new(data: data, changed: false) if exists == present
        mutate(client, card, id, present, data)
      end

      def self.mutate(client, card, id, present, data)
        response = present ? client.add_card_label(card, id) : client.remove_card_label(card, id)
        item = response["item"]
        unless item.is_a?(Hash) && item["cardId"] == card && item["labelId"] == id
          raise InvalidResponse, "Invalid relationship write response"
        end
        MutationResult.new(data: data, changed: true)
      rescue Client::UnknownOutcome, InvalidResponse
        raise MutationFailure.new(data: data, changed: nil, uncertain: true,
          recovery: { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => card }] })
      end
      private_class_method :mutate
    end
  end
end
