module Planka
  class Tasks
    module Create
      def self.read(client, base_url:, task_list_id:, attributes:, linked_card: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: nil, card_id: card_id, task_list_id: task_list_id, board_id: board_id)
        snapshot = Snapshot.new(card)
        list = snapshot.list(task_list_id)
        attrs = prepared_attributes(client, snapshot, list, attributes, linked_card)
        mutate(client, snapshot, list, attrs)
      end

      def self.prepared_attributes(client, snapshot, list, attributes, linked_card)
        data = snapshot.list_tasks(list["id"])
        attrs = positioned_attributes(attributes, data)
        return attrs unless linked_card

        card_id = linked_card_id(client, snapshot, linked_card)
        linked_attributes(attrs, card_id)
      end

      def self.positioned_attributes(attributes, tasks)
        attrs = attributes.dup
        attrs["position"] ||= Position.after(tasks)
        attrs
      end

      def self.linked_attributes(attributes, card_id) = attributes.merge("linkedCardId" => card_id)

      def self.linked_card_id(client, snapshot, reference)
        card = Cards::Scope.card(client, card_id: reference, board_id: snapshot.board_id)
        Cards::Scope.card_id(card)
      end

      def self.expected_response(list, attributes) = attributes.merge("taskListId" => list["id"])
      def self.known_resource(snapshot, list) = { "id" => nil, "cardId" => snapshot.card_id, "taskListId" => list["id"] }

      def self.mutate(client, snapshot, list, attributes)
        Write.perform(snapshot, known_resource(snapshot, list), expected: expected_response(list, attributes), operation: :create) do
          client.create_task(list["id"], **attributes.transform_keys(&:to_sym))
        end
      end
      private_class_method :prepared_attributes, :positioned_attributes, :linked_attributes, :linked_card_id, :expected_response, :known_resource, :mutate
    end
  end
end
