module Planka
  class Tasks
    module Update
      def self.read(client, reference, base_url:, attributes:, assignee: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: nil, board_id: board_id)
        snapshot = Snapshot.new(card)
        task = snapshot.task(reference)
        validate_editable_fields!(task, attributes, assignee)
        attrs = resolved_attributes(client, snapshot, attributes, assignee)
        return unchanged_result(task) if unchanged?(task, attrs)

        mutate(client, snapshot, task, attrs)
      end

      def self.validate_editable_fields!(task, attributes, assignee)
        if task["linkedCardId"] && (assignee || (attributes.keys - ["position"]).any?)
          raise ReferenceError.new("Linked tasks accept position updates only", code: "linked_task", status: 1)
        end
      end

      def self.resolved_attributes(client, snapshot, attributes, assignee)
        attrs = attributes.dup
        attrs["assigneeUserId"] = Users.resolve(client, assignee, snapshot.board_id) if assignee
        attrs
      end

      def self.unchanged?(task, attributes) = attributes.all? { |key, value| task[key] == value }
      def self.unchanged_result(task) = MutationResult.new(data: task, changed: false)

      def self.expected_response(task, attributes)
        task.slice("taskListId", "name", "isCompleted", "assigneeUserId", "linkedCardId").merge(attributes)
      end

      def self.mutate(client, snapshot, task, attributes)
        Write.perform(snapshot, task, expected: expected_response(task, attributes), operation: :update, changed_fields: attributes.keys) do
          client.update_task(task["id"], **attributes.transform_keys(&:to_sym))
        end
      end
      private_class_method :validate_editable_fields!, :resolved_attributes, :unchanged?, :unchanged_result, :expected_response, :mutate
    end
  end
end
