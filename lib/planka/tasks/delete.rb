module Planka
  class Tasks
    module Delete
      def self.read(client, reference, base_url:, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        task = snapshot.task(reference)
        Write.perform(snapshot, task, expected: task.slice("taskListId"), operation: :delete, changed_fields: []) do
          client.delete_task(task["id"])
        end
      end
    end
  end
end
