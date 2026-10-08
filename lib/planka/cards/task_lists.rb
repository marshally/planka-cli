module Planka
  module Cards
    # Reads and changes native card task lists. An explicit task-list ID
    # determines its own card; names resolve within the asserted card. Each
    # operation observes current server state through the supplied client.
    class TaskLists < Resource
      def initialize(client, card_id: nil, board_id: nil)
        super(client)
        @scope = TaskListScope.new(client, card_id: card_id, board_id: board_id)
      end

      def find(reference) = read_record(reference)

      private

      def read_record(reference) = TaskListRecord.data(@scope.task_lists(@scope.card(reference), reference).first)
    end
  end
end
