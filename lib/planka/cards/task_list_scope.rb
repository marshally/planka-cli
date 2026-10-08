module Planka
  module Cards
    # Resolves the card and task lists an operation works in. An explicit card
    # asserts the parent; a task-list ID alone finds its own card.
    class TaskListScope
      def initialize(client, card_id: nil, board_id: nil)
        @client, @card_id, @board_id = client, card_id, board_id
      end

      def card(task_list)
        Scope.card(@client, card_id: @card_id || task_list_card(task_list), board_id: @board_id)
      end

      # The card's task lists in card order, or the one TASK_LIST resolved within them.
      def task_lists(card, task_list = nil)
        task_lists = card_task_lists(card)
        return task_lists unless task_list
        if Records.id?(task_list) && task_lists.none? { |record| record["id"] == task_list }
          raise ReferenceError, "Task list does not belong to --card"
        end

        [Reference.resolve(task_lists, task_list, resource: "task list", scope: "the card")]
      end

      private

      def task_list_card(task_list)
        raise ArgumentError, "task list names require a card" unless Records.id?(task_list)

        record = @client.task_list(task_list)
        raise InvalidResponse, "Invalid task list record" unless record["id"] == task_list && Records.id?(record["cardId"])

        record["cardId"]
      end

      def card_task_lists(card)
        included = card["included"]
        task_lists = included["taskLists"] if included.is_a?(Hash)
        unless task_lists.is_a?(Array) && task_lists.all? { |record| TaskListRecord.valid?(record) && record["cardId"] == Scope.card_id(card) } &&
               task_lists.map { |record| record["id"] }.uniq.size == task_lists.size
          raise InvalidResponse, "Invalid card task lists"
        end

        task_lists.sort_by { |record| [record["position"], record["id"].to_i] }
      end
    end
  end
end
