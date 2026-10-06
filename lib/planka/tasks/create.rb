module Planka
  class Tasks
    module Create
      def self.read(client, base_url:, task_list_id:, attributes:, linked_card: nil, card_id: nil, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        card = Scope.load(client, reference: nil, card_id: card_id, task_list_id: task_list_id, board_id: board_id)
        snapshot = Snapshot.new(card)
        list = snapshot.list(task_list_id)
        data = []
        snapshot.hydrate!(data, list_id: list["id"])
        attrs = attributes.dup
        attrs["position"] ||= Position.after(data)
        if linked_card
          linked = Cards::Scope.card(client, card_id: linked_card, board_id: snapshot.board_id)
          attrs["linkedCardId"] = Cards::Scope.card_id(linked)
        end
        expected = attrs.merge("taskListId" => list["id"])
        known = { "id" => nil, "cardId" => snapshot.card_id, "taskListId" => list["id"] }
        Write.perform(snapshot, known, expected: expected, operation: :create) do
          client.create_task(list["id"], **attrs.transform_keys(&:to_sym))
        end
      end
    end
  end
end
