module Planka
  class Tasks
    module Update
      def self.read(client, reference, base_url:, attributes:, assignee: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        tasks = []
        snapshot.hydrate!(tasks)
        task = Reference.resolve(tasks, reference, resource: "task", scope: "the card")
        attrs = attributes.dup
        if task["linkedCardId"] && (assignee || (attrs.keys - ["position"]).any?)
          raise ReferenceError.new("Linked tasks accept position updates only", code: "linked_task", status: 1)
        end

        attrs["assigneeUserId"] = Users.resolve(client, assignee, snapshot.board_id) if assignee
        return MutationResult.new(data: task, changed: false) if attrs.all? { |key, value| task[key] == value }

        expected = task.slice("taskListId", "name", "isCompleted", "assigneeUserId", "linkedCardId").merge(attrs)
        Write.perform(snapshot, task, expected: expected, operation: :update, changed_fields: attrs.keys) do
          client.update_task(task["id"], **attrs.transform_keys(&:to_sym))
        end
      end
    end
  end
end
