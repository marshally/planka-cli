module Planka
  class Tasks
    module Move
      def self.read(client, reference, base_url:, destination:, position: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        task = snapshot.task(reference)
        list = snapshot.list(destination)
        if task["taskListId"] == list["id"] && (position.nil? || position == task["position"])
          return MutationResult.new(data: task, changed: false)
        end

        attrs = { "taskListId" => list["id"], "position" => position || Position.after(snapshot.list_tasks(list["id"])) }
        expected = task.slice("name", "isCompleted", "assigneeUserId", "linkedCardId").merge(attrs)
        Write.perform(snapshot, task, expected: expected, operation: :move, changed_fields: attrs.keys) do
          client.update_task(task["id"], **attrs.transform_keys(&:to_sym))
        end
      end
    end
  end
end
