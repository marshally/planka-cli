module Planka
  module Cards
    # Locates the card a card-scoped resource command targets: by ID, or by exact
    # name within an asserted board. Returns the card response and its board.
    module Scope
      def self.read(client, card_id:, board_id:)
        unless Records.id?(card_id)
          board = client.board(board_id)
          card_id = resolve_name(card_id, board, board_id)
        end
        card = client.card(card_id)
        item = card["item"]
        unless item.is_a?(Hash) && item["id"] == card_id && Records.id?(item["boardId"])
          raise InvalidResponse, "Invalid scoped card"
        end
        raise ReferenceError, "Card does not belong to --board" if board_id && board_id != item["boardId"]
        [card, board || client.board(item["boardId"])]
      end

      def self.resolve_name(name, board, board_id)
        cards = board["cards"]
        unless cards.is_a?(Array) && cards.all? { |record| record.is_a?(Hash) && Records.id?(record["id"]) &&
            record["boardId"] == board_id && record["name"].is_a?(String) } &&
            cards.map { |record| record["id"] }.uniq.size == cards.size
          raise InvalidResponse, "Invalid card name scope"
        end
        Reference.resolve(cards, name, resource: "card").fetch("id")
      end
      private_class_method :resolve_name
    end
  end
end
