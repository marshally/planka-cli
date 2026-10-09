module Planka
  module Boards
    # Resolves the board and lists an operation works in. An explicit board
    # asserts the parent; a list ID alone finds its own active/closed board.
    class ListScope
      TYPES = %w[active closed archive trash].freeze
      FINITE_TYPES = %w[active closed].freeze

      # parent names the asserted board in mismatch errors.
      def initialize(client, board_id: nil, parent: "--board")
        @client, @board_id, @parent = client, board_id, parent
      end

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

        [resolve_list(lists, list)]
      end

      def finite?(list) = FINITE_TYPES.include?(list["type"])

      private

      # Name lookup observes server state, so ambiguity and absence are
      # operational failures. Explicit parent mismatches remain local input.
      def resolve_list(lists, reference)
        Reference.resolve(lists, reference, resource: "list", scope: "the board")
      rescue ReferenceError => error
        raise ReferenceError.new(error.message, code: error.code, status: 1)
      end

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
        record.is_a?(Hash) && Records.id?(record["id"]) && record["boardId"] == board_id && TYPES.include?(record["type"]) &&
          (record["name"].nil? || record["name"].is_a?(String)) && (record["position"].nil? || record["position"].is_a?(Numeric))
      end
    end
  end
end
