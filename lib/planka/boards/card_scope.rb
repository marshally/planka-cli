module Planka
  module Boards
    # Resolves the card, board, and lists a card operation works in. An explicit
    # board asserts the parent; a list ID alone finds its own active/closed board.
    class CardScope
      LIST_TYPES = %w[active closed archive trash].freeze
      FINITE_LIST_TYPES = %w[active closed].freeze
      CARD_TYPES = %w[project story].freeze

      # A card's public data with the destination it is being created or moved in.
      Observation = Data.define(:card, :destination)

      # A verified list a card is created or moved into.
      Destination = Data.define(:board_id, :list_id, :finite, :append_position, :card_type) do
        # Active/closed lists append unless positioned; archive/trash take none.
        def position(requested)
          return requested || append_position if finite
          raise ReferenceError, "Archive and trash lists do not accept --position" if requested
        end
      end

      # parent names the asserted board in mismatch errors.
      def initialize(client, board_id: nil, parent: "--board")
        @client, @board_id, @parent = client, board_id, parent
      end

      def card(reference) = CardRecord.data(Planka::Cards::Scope.card(@client, card_id: reference, board_id: @board_id).fetch("item"))

      def board(list)
        board_id = @board_id || list_board(list)
        board = @client.board_document(board_id)
        raise InvalidResponse, "Invalid board record" unless board["item"]["id"] == board_id

        board
      end

      # The board's lists in board order, or the one LIST resolved within them.
      def lists(board, list = nil)
        lists = board_lists(board)
        return lists unless list
        raise ReferenceError, "List does not belong to #{@parent}" if Records.id?(list) && lists.none? { |record| record["id"] == list }

        [Reference.resolve(lists, list, resource: "list", scope: "the board")]
      end

      def finite?(list) = FINITE_LIST_TYPES.include?(list["type"])

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
        Destination.new(board_id: board["item"]["id"], list_id: record["id"], finite: finite?(record), card_type: card_type(board),
                        append_position: (Position.after(list_cards(board, record, excluding: excluding)) if finite?(record)))
      end

      private

      def list_board(list)
        raise ArgumentError, "list names require a board" unless Records.id?(list)

        record = listed(list)
        raise InvalidResponse, "Invalid list record" unless record["id"] == list && Records.id?(record["boardId"])

        record["boardId"]
      end

      # Planka reads only active/closed lists individually, answering 404 otherwise.
      def listed(list)
        @client.list(list)
      rescue Client::HTTPError => error
        raise unless error.status == 404

        raise ReferenceError.new("List not found as an active or closed list; archive and trash lists need --board",
                                 code: "not_found", status: 1)
      end

      def board_lists(board)
        lists = board["included"]["lists"]
        raise InvalidResponse, "Invalid board lists" unless lists.is_a?(Array) && lists.all? { |record| list?(record, board["item"]["id"]) }

        lists.sort_by { |record| [finite?(record) ? 0 : 1, record["position"].to_f, record["id"].to_i] }
      end

      def list?(record, board_id)
        record.is_a?(Hash) && Records.id?(record["id"]) && record["boardId"] == board_id && LIST_TYPES.include?(record["type"]) &&
          (record["name"].nil? || record["name"].is_a?(String)) && (record["position"].nil? || record["position"].is_a?(Numeric))
      end

      def scoped_card!(card, list)
        CardRecord.data(card)
        raise InvalidResponse, "Card outside its list scope" unless card["listId"] == list["id"] && card["boardId"] == list["boardId"]
      end

      def card_type(board)
        type = board["item"]["defaultCardType"]
        raise InvalidResponse, "Invalid board default card type" unless CARD_TYPES.include?(type)

        type
      end
    end
  end
end
