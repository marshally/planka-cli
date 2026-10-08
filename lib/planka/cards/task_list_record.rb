module Planka
  module Cards
    # The task-list fields Planka accepts and returns: input limits, the
    # validated public projection, write confirmation, and read-back recovery.
    module TaskListRecord
      FIELDS = %w[id cardId name position showOnFrontOfCard hideCompletedTasks createdAt updatedAt].freeze
      NAME_LIMIT = 128

      def self.name!(name)
        return name if Records.text?(name, NAME_LIMIT)

        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} characters"
      end

      def self.position!(position)
        return position if Records.position?(position)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def self.data(record)
        raise InvalidResponse, "Invalid task list record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      # A task list not yet created: only its card is known.
      def self.placeholder(card_id) = FIELDS.to_h { |field| [field, nil] }.merge("cardId" => card_id)

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.id?(record["cardId"]) && record["name"].is_a?(String) &&
          Records.position?(record["position"]) && %w[showOnFrontOfCard hideCompletedTasks].all? { |field| [true, false].include?(record[field]) } &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end

      # The written task list is the requested one; Planka may renumber
      # positions among the card's task lists, so only the rest is compared.
      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || record["id"] == desired["id"]) &&
               %w[cardId name].all? { |field| record[field] == desired[field] }
          raise InvalidResponse, "Invalid task list write response"
        end
      end

      def self.recovery(task_list)
        return { "action" => "readback-task-list", "resources" => [{ "type" => "task-list", "id" => task_list["id"] }] } if task_list["id"]

        { "action" => "readback-task-lists", "resources" => [{ "type" => "card", "id" => task_list["cardId"] }] }
      end
    end
  end
end
