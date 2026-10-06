module Planka
  class Tasks
    # Validates task hydration and projects only the fields in the task contract.
    class Snapshot
      attr_reader :card_id, :board_id, :lists

      def initialize(card)
        @card_id = Cards::Scope.card_id(card)
        @board_id = Cards::Scope.board_id(card)
        included = card["included"]
        raise InvalidResponse, "Invalid task card" unless included.is_a?(Hash)

        @lists, @tasks = included.values_at("taskLists", "tasks")
        unless @lists.is_a?(Array) && @lists.all? { |list|
          list.is_a?(Hash) && Records.id?(list["id"]) && list["cardId"] == @card_id &&
          list["name"].is_a?(String) && self.class.position?(list["position"])
        } && @lists.map { |list| list["id"] }.uniq.size == @lists.size && @tasks.is_a?(Array)
          raise InvalidResponse, "Invalid task-list records"
        end
      end

      def list(reference) = Reference.resolve(@lists, reference, resource: "task list", scope: "the card")

      def hydrate!(data, list_id: nil)
        @tasks.each do |task|
          self.class.validate!(task)
          raise InvalidResponse, "Invalid task parent" unless @lists.any? { |list| list["id"] == task["taskListId"] }
          raise InvalidResponse, "Duplicate task" if data.any? { |record| record["id"] == task["id"] }

          data << project(task)
        end
        data.select! { |task| task["taskListId"] == list_id } if list_id
      end

      def ordered(data)
        data.sort_by do |task|
          parent = @lists.find { |list| list["id"] == task["taskListId"] }
          [parent["position"], parent["id"].to_i, task["position"], task["id"].to_i]
        end
      end

      def project(task)
        task.slice("id", "taskListId", "name", "position", "isCompleted").merge(
          "cardId" => @card_id, "assigneeUserId" => task["assigneeUserId"], "linkedCardId" => task["linkedCardId"],
          "createdAt" => task["createdAt"], "updatedAt" => task["updatedAt"]
        )
      end

      def self.position?(value) = value.is_a?(Numeric) && value.finite? && value >= 0

      def self.validate!(task)
        unless task.is_a?(Hash) && Records.id?(task["id"]) && Records.id?(task["taskListId"]) &&
               task["name"].is_a?(String) && !task["name"].empty? && position?(task["position"]) &&
               [true, false].include?(task["isCompleted"]) &&
               %w[assigneeUserId linkedCardId].all? { |key| task[key].nil? || Records.id?(task[key]) } &&
               %w[createdAt updatedAt].all? { |key| task[key].nil? || Records.timestamp?(task[key]) }
          raise InvalidResponse, "Invalid task record"
        end
      end
    end
  end
end
