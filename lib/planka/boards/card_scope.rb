module Planka
  module Boards
    # Resolves the card, board, and lists a card operation works in. ListScope
    # owns board and list resolution; this adds cards and their destinations.
    class CardScope
      CARD_TYPES = %w[project story].freeze

      # A card's public data with the destination it is being created or moved in.
      Observation = Data.define(:card, :destination)

      # A verified list a card is created or moved into.
      Destination = Data.define(:board_id, :list_id, :finite, :append_position, :default_card_type) do
        # Active/closed lists append unless positioned; archive/trash take none.
        def position(requested)
          return requested || append_position if finite
          raise ReferenceError, "Archive and trash lists do not accept --position" if requested
        end
      end

      # parent names the asserted board in mismatch errors.
      def initialize(client, board_id: nil, parent: "--board")
        @client, @board_id = client, board_id
        @lists = ListScope.new(client, board_id: board_id, parent: parent)
      end

      def card(reference) = CardRecord.data(Planka::Cards::Scope.card(@client, card_id: reference, board_id: @board_id).fetch("item"))
      def board(list) = @lists.board(list)
      def lists(board, list = nil) = @lists.lists(board, list)
      def finite?(list) = @lists.finite?(list)

      # A finite list's validated cards from the board read.
      def list_cards(board, list, excluding: nil)
        cards = board["included"]["cards"]
        raise InvalidResponse, "Invalid board cards" unless cards.is_a?(Array) && cards.all?(Hash)

        cards.select { |card| card["listId"] == list["id"] && card["id"] != excluding }.each { |card| scoped_card!(card, list) }
      end

      # The verified destination list and the position that appends to it.
      def destination(list, excluding: nil)
        board = board(list)
        record = lists(board, list).first
        Destination.new(board_id: board["item"]["id"], list_id: record["id"], finite: finite?(record), default_card_type: default_card_type(board),
                        append_position: (Position.after(list_cards(board, record, excluding: excluding)) if finite?(record)))
      end

      private

      def scoped_card!(card, list)
        CardRecord.data(card)
        raise InvalidResponse, "Card outside its list scope" unless card["listId"] == list["id"] && card["boardId"] == list["boardId"]
      end

      def default_card_type(board)
        type = board["item"]["defaultCardType"]
        raise InvalidResponse, "Invalid board default card type" unless CARD_TYPES.include?(type)

        type
      end
    end
  end
end
