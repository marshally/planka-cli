module Planka
  module Boards
    # Reads and changes native board lists. An explicit list ID determines its
    # own board; names resolve within the asserted board. Each operation observes
    # current server state through the supplied authenticated client.
    class Lists < Resource
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def initialize(client, board_id: nil)
        super(client)
        @board_id = board_id
        @scope = ListScope.new(client, board_id: board_id)
      end

      # Every list on the board, of every native type, matching an exact name.
      # Active/closed lists come first by position, then archive and trash.
      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)
        data = []
        @scope.lists(@scope.board(nil)).each { |record| data << ListRecord.data(record) if name.nil? || record["name"] == name }
        CollectionResult.limited(data, limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: CollectionResult.limited(data, limit).data)
      end

      def find(reference) = read_record(reference)

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "lists are read from a board" unless @board_id
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference) = ListRecord.data(@scope.lists(@scope.board(reference), reference).first)
    end
  end
end
