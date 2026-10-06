module Planka
  module Cards
    # One association; the label resolves among the card's own board labels.
    class Labels
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def self.read(client, label, card:, present:, base_url:)
        response = client.card(card)
        item, included = response.values_at("item", "included")
        unless item.is_a?(Hash) && item["id"] == card && item["boardId"].is_a?(String) && included.is_a?(Hash)
          raise InvalidResponse, "Invalid label card"
        end
        id = Reference.resolve(board_labels(client, item["boardId"]), label, resource: "label").fetch("id")
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
      rescue *OPERATION_ERRORS => error
        uncertain = !Client.unapplied?(error)
        raise MutationFailure.new(data: data.merge("present" => uncertain ? nil : !present),
          changed: uncertain ? nil : false, uncertain: uncertain,
          recovery: { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => card }] })
      end

      def self.board_labels(client, board_id)
        labels = client.board(board_id)["labels"]
        unless labels.is_a?(Array) && labels.all? { |record| record.is_a?(Hash) && Records.id?(record["id"]) &&
            record["boardId"] == board_id && (record["name"].nil? || record["name"].is_a?(String)) } &&
            labels.map { |record| record["id"] }.uniq.size == labels.size
          raise InvalidResponse, "Invalid board labels"
        end
        labels
      end
      private_class_method :mutate, :board_labels
    end
  end
end
