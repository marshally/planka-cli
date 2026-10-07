module Planka
  module Cards
    # Updates ordinary task completion within one card scope.
    class Tasks
      def initialize(client, card_id:, board_id: nil)
        @client, @card_id, @board_id = client, card_id, board_id
      end

      def update(reference, completed:)
        validate_completion!(completed)
        data = task_data(reference)
        return MutationResult.new(data: data, changed: false) if data["isCompleted"] == completed

        mutate(data, completed)
      end

      private

      def validate_completion!(completed)
        raise ArgumentError, "completed must be true or false" unless [true, false].include?(completed)
      end

      def task_data(reference)
        card = Scope.card(@client, card_id: @card_id, board_id: @board_id)
        task = ordinary_task(card, reference)
        task.slice("id", "name", "taskListId", "isCompleted").merge("cardId" => Scope.card_id(card))
      end

      def ordinary_task(card, reference)
        task = Reference.resolve(card_tasks(card), reference, resource: "task", scope: "the card")
        if task["linkedCardId"]
          raise ReferenceError.new("Linked tasks follow their blocker card; never complete them manually", code: "linked_task", status: 1)
        end

        task
      end

      def card_tasks(card)
        included = card["included"]
        raise InvalidResponse, "Invalid task card" unless included.is_a?(Hash)

        lists, tasks = included.values_at("taskLists", "tasks")
        unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && list["cardId"] == Scope.card_id(card) && list["id"].is_a?(String) } &&
               tasks.is_a?(Array) && tasks.all? { |task|
                                       task.is_a?(Hash) && task["id"].is_a?(String) && task["name"].is_a?(String) &&
                                       [true, false].include?(task["isCompleted"]) && lists.any? { |list| list["id"] == task["taskListId"] }
                                     }
          raise InvalidResponse, "Invalid card task records"
        end

        tasks
      end

      def mutate(data, completed)
        Write.perform(unchanged: data, unknown: data.merge("isCompleted" => nil), recovery: recovery(data)) do
          confirm_write!(@client.update_task(data["id"], isCompleted: completed), data, completed)
          data.merge("isCompleted" => completed)
        end
      end

      def confirm_write!(updated, data, completed)
        unless updated.is_a?(Hash) && updated["id"] == data["id"] && updated["taskListId"] == data["taskListId"] && updated["isCompleted"] == completed
          raise InvalidResponse, "Invalid task update response"
        end
      end

      def recovery(data)
        { "action" => "readback-task", "resources" => [{ "type" => "card", "id" => data["cardId"] }, { "type" => "task", "id" => data["id"] }] }
      end
    end
  end
end
