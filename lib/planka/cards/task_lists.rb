module Planka
  module Cards
    # Reads and changes native card task lists. An explicit task-list ID
    # determines its own card; names resolve within the asserted card. Each
    # operation observes current server state through the supplied client.
    class TaskLists < Resource
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def initialize(client, card_id: nil, board_id: nil)
        super(client)
        @card_id = card_id
        @scope = TaskListScope.new(client, card_id: card_id, board_id: board_id)
      end

      # Every task list on the card, in card order, matching an exact name.
      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)
        data = []
        @scope.task_lists(@scope.card(nil)).each { |record| data << TaskListRecord.data(record) if name.nil? || record["name"] == name }
        CollectionResult.limited(data, limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: CollectionResult.limited(data, limit).data)
      end

      def find(reference) = read_record(reference)

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "task lists are read from a card" unless @card_id
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference) = TaskListRecord.data(@scope.task_lists(@scope.card(reference), reference).first)
    end
  end
end
