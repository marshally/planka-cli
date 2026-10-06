module Planka
  class Tasks
    module Move
      def self.read(client, reference, base_url:, destination:, position: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        task = snapshot.task(reference)
        list = snapshot.list(destination)
        return unchanged_result(task) if already_positioned?(task, list, position)

        attrs = positioned_attributes(snapshot, list, position)
        mutate(client, snapshot, task, attrs)
      end

      def self.already_positioned?(task, list, position)
        task["taskListId"] == list["id"] && (position.nil? || position == task["position"])
      end

      def self.unchanged_result(task) = MutationResult.new(data: task, changed: false)

      def self.positioned_attributes(snapshot, list, position)
        { "taskListId" => list["id"], "position" => position || Position.after(snapshot.list_tasks(list["id"])) }
      end

      def self.expected_response(task, attributes)
        task.slice("name", "isCompleted", "assigneeUserId", "linkedCardId").merge(attributes)
      end

      def self.mutate(client, snapshot, task, attributes)
        Write.perform(snapshot, task, expected: expected_response(task, attributes), operation: :move, changed_fields: attributes.keys) do
          client.update_task(task["id"], **attributes.transform_keys(&:to_sym))
        end
      end
      private_class_method :already_positioned?, :unchanged_result, :positioned_attributes, :expected_response, :mutate
    end
  end
end
