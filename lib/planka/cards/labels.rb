module Planka
  module Cards
    # Observes a card's labels, then sets one verified card-label relationship.
    class Labels < Resource
      include Relationship

      def initialize(client, card_id:, board_id: nil)
        super(client)
        @card_id, @board_id = card_id, board_id
      end

      private

      def read_record(reference)
        card, board = Scope.read(client, card_id: @card_id, board_id: @board_id)
        label_id = resolve_label(reference, board, card)
        { "cardId" => Scope.card_id(card), "labelId" => label_id, "present" => applied?(card, label_id) }
      end

      def resolve_label(label, board, card)
        Reference.resolve(board_labels(board, Scope.board_id(card)), label, resource: "label").fetch("id")
      end

      def applied?(card, label_id) = applied_labels(card).any? { |entry| entry["labelId"] == label_id }

      def applied_labels(card)
        included = card["included"]
        raise InvalidResponse, "Invalid card relations" unless included.is_a?(Hash)

        applied = included["cardLabels"]
        unless applied.is_a?(Array) && applied.all? { |entry|
          entry.is_a?(Hash) &&
          entry["cardId"] == Scope.card_id(card) && entry["labelId"].is_a?(String)
        }
          raise InvalidResponse, "Invalid card label records"
        end

        applied
      end

      def board_labels(board, board_id)
        labels = board["labels"]
        unless labels.is_a?(Array) && labels.all? { |record|
          record.is_a?(Hash) && Records.id?(record["id"]) &&
          record["boardId"] == board_id && (record["name"].nil? || record["name"].is_a?(String))
        } &&
               labels.map { |record| record["id"] }.uniq.size == labels.size
          raise InvalidResponse, "Invalid board labels"
        end

        labels
      end

      def relationship_present?(known) = known.fetch("present")
      def relationship_data(known, present:) = known.merge("present" => present)

      def create_record(known) = client.add_card_label(known["cardId"], known["labelId"])["item"]
      def delete_record(known) = client.remove_card_label(known["cardId"], known["labelId"])["item"]

      def validate_record!(item, desired)
        unless item.is_a?(Hash) && item["cardId"] == desired["cardId"] && item["labelId"] == desired["labelId"]
          raise InvalidResponse, "Invalid relationship write response"
        end
      end

      def recovery(known)
        { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => known["cardId"] }] }
      end
    end
  end
end
