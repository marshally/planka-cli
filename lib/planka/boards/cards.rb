module Planka
  module Boards
    # Reads and changes native cards. An explicit card ID determines its own
    # board; names resolve within the asserted board. Each operation observes
    # current server state through the supplied authenticated client.
    class Cards < Resource
      FIELDS = %w[id name description type boardId listId position createdAt updatedAt].freeze

      def initialize(client, board_id: nil)
        super(client)
        @board_id = board_id
      end

      def find(reference) = read_record(reference)

      private

      def read_record(reference)
        card_data(Planka::Cards::Scope.card(client, card_id: reference, board_id: @board_id).fetch("item"))
      end

      def card_data(record)
        raise InvalidResponse, "Invalid card record" unless card?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def card?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && record["name"].is_a?(String) &&
          (record["description"].nil? || record["description"].is_a?(String)) && record["type"].is_a?(String) &&
          Records.id?(record["boardId"]) && Records.id?(record["listId"]) &&
          (record["position"].nil? || (record["position"].is_a?(Numeric) && record["position"].finite?)) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
