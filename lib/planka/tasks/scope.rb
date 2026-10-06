module Planka
  class Tasks
    # Finds the owning card from explicit scope or native accessible-board snapshots.
    # There is no native task/task-list GET endpoint in Community v2.2.1.
    module Scope
      def self.load(client, reference:, card_id:, task_list_id:, board_id:)
        if card_id
          return Cards::Scope.card(client, card_id: card_id, board_id: board_id)
        end

        board_ids = board_id ? [board_id] : client.board_ids
        board_ids.each do |id|
          board = client.board(id)
          owner = owner_id(board, reference, task_list_id)
          return Cards::Scope.card(client, card_id: owner, board_id: id) if owner
        end
        resource = task_list_id ? "Task list" : "Task"
        raise ReferenceError.new("#{resource} not found in accessible board snapshots; supply --card for a known card", code: "not_found", status: 1)
      end

      def self.owner_id(board, reference, task_list_id)
        lists, tasks = board.values_at("taskLists", "tasks")
        unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && Records.id?(list["id"]) && Records.id?(list["cardId"]) } &&
               tasks.is_a?(Array) && tasks.all? { |task| task.is_a?(Hash) && Records.id?(task["id"]) && lists.any? { |list| list["id"] == task["taskListId"] } } &&
               lists.map { |list| list["id"] }.uniq.size == lists.size && tasks.map { |task| task["id"] }.uniq.size == tasks.size
          raise InvalidResponse, "Invalid task discovery records"
        end

        list_id = task_list_id || tasks.find { |task| task["id"] == reference }&.fetch("taskListId")
        lists.find { |list| list["id"] == list_id }&.fetch("cardId")
      end
      private_class_method :owner_id
    end
  end
end
