module Planka
  module Cards
    # The task-list fields Planka accepts and returns: input limits and the
    # validated public projection.
    module TaskListRecord
      FIELDS = %w[id cardId name position showOnFrontOfCard hideCompletedTasks createdAt updatedAt].freeze

      def self.data(record)
        raise InvalidResponse, "Invalid task list record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.id?(record["cardId"]) && record["name"].is_a?(String) &&
          Records.position?(record["position"]) && %w[showOnFrontOfCard hideCompletedTasks].all? { |field| [true, false].include?(record[field]) } &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
