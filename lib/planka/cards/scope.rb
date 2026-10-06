module Planka
  module Cards
    # Locates the card a card-scoped resource command targets: by ID, or by exact
    # name within an asserted board. Returns the card response and its board.
    module Scope
      def self.read(client, card_id:, board_id:)
        card, named_board = locate(client, card_id, board_id)
        [card, named_board || client.board(self.board_id(card))]
      end

      # The verified card alone, for commands that need nothing from its board.
      def self.card(client, card_id:, board_id:) = locate(client, card_id, board_id).first

      def self.card_id(card) = card.fetch("item").fetch("id")
      def self.board_id(card) = card.fetch("item").fetch("boardId")

      def self.resolve_name(name, board, board_id)
        cards = board["cards"]
        unless cards.is_a?(Array) && cards.all? { |record|
          record.is_a?(Hash) && Records.id?(record["id"]) &&
          record["boardId"] == board_id && record["name"].is_a?(String)
        } &&
               cards.map { |record| record["id"] }.uniq.size == cards.size
          raise InvalidResponse, "Invalid card name scope"
        end

        Reference.resolve(cards, name, resource: "card").fetch("id")
      end

      def self.locate(client, card_id, board_id)
        named_board = client.board(board_id) unless Records.id?(card_id)
        card_id = resolve_name(card_id, named_board, board_id) if named_board
        [verified_card(client, card_id, board_id), named_board]
      end

      # The card exists as requested and, when --board was given, belongs to it.
      def self.verified_card(client, card_id, board_id)
        card = client.card(card_id)
        item = card["item"]
        unless item.is_a?(Hash) && item["id"] == card_id && Records.id?(item["boardId"])
          raise InvalidResponse, "Invalid scoped card"
        end
        raise ReferenceError, "Card does not belong to --board" if board_id && board_id != item["boardId"]

        card
      end
      private_class_method :locate, :resolve_name, :verified_card
    end
  end
end
