module Planka
  module Cards
    # Observes a card's tasks, then sets one ordinary task's verified completion.
    class Tasks
      class << self
        def read(client, reference, card_id:, completed:, base_url:, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- base_url is part of the shared prepared-reader contract.
          card = Scope.card(client, card_id: card_id, board_id: board_id)
          task = ordinary_task(card, reference)
          data = task.slice("id", "name", "taskListId", "isCompleted").merge("cardId" => Scope.card_id(card))
          return MutationResult.new(data: data, changed: false) if task["isCompleted"] == completed

          mutate(client, data, completed)
        end

        private

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

        def mutate(client, data, completed)
          Write.perform(unchanged: data, unknown: data.merge("isCompleted" => nil), recovery: recovery(data)) do
            confirm_write!(client.update_task(data["id"], isCompleted: completed), data, completed)
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
end
