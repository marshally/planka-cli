module Planka
  class Tasks
    module Move
      def self.read(client, reference, base_url:, destination:, position: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        tasks = []
        snapshot.hydrate!(tasks)
        task = Reference.resolve(tasks, reference, resource: "task", scope: "the card")
        list = snapshot.list(destination)
        if task["taskListId"] == list["id"] && (position.nil? || position == task["position"])
          return MutationResult.new(data: task, changed: false)
        end

        attrs = { "taskListId" => list["id"], "position" => position || Position.after(tasks.select { |entry| entry["taskListId"] == list["id"] }) }
        expected = task.slice("name", "isCompleted", "assigneeUserId", "linkedCardId").merge(attrs)
        Write.perform(snapshot, task, expected: expected, operation: :move, changed_fields: attrs.keys) do
          client.update_task(task["id"], **attrs.transform_keys(&:to_sym))
        end
      end
    end
  end
end
