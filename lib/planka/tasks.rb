require "planka/tasks/scope"
require "planka/tasks/snapshot"

module Planka
  # Native tasks, independent of workflow checklist and blocker conventions.
  class Tasks
    OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

    def self.read(client, reference = nil, base_url:, card_id: nil, task_list_id: nil, board_id: nil, filters: {}, limit: nil, assignee: nil, linked_card: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
      data = []
      card = Scope.load(client, reference: reference, card_id: card_id, task_list_id: task_list_id, board_id: board_id)
      snapshot = Snapshot.new(card)
      filters = resolved_filters(client, snapshot, filters, assignee, linked_card)
      list = snapshot.list(task_list_id) if task_list_id
      filters = filters.merge("taskListId" => list["id"]) if list
      snapshot.hydrate!(data)
      if reference
        scoped = list ? data.select { |task| task["taskListId"] == list["id"] } : data
        return Reference.resolve(scoped, reference, resource: "task", scope: "the card")
      end

      collection(snapshot.ordered(data), filters, limit)
    rescue *OPERATION_ERRORS => error
      raise if reference || error.is_a?(ReferenceError)

      raise CollectionFailure.new(data: collection(snapshot ? snapshot.ordered(data) : data, filters, limit).data)
    end

    def self.resolved_filters(client, snapshot, filters, assignee, linked_card)
      filters = filters.dup
      filters["assigneeUserId"] = Records.id?(assignee) ? assignee : Users.resolve(client, assignee, snapshot.board_id) if assignee
      if linked_card
        filters["linkedCardId"] = if Records.id?(linked_card)
                                    linked_card
                                  else
                                    Cards::Scope.card_id(Cards::Scope.card(client, card_id: linked_card, board_id: snapshot.board_id))
                                  end
      end
      filters
    end

    def self.collection(data, filters, limit)
      data = data.select { |task| filters.all? { |key, value| task[key] == value } }
      CollectionResult.new(data: limit ? data.first(limit) : data, complete: !limit || data.size <= limit)
    end
    private_class_method :collection, :resolved_filters
  end
end

require "planka/tasks/write"
require "planka/tasks/create"
require "planka/tasks/users"
require "planka/tasks/update"
require "planka/tasks/move"
require "planka/tasks/delete"
