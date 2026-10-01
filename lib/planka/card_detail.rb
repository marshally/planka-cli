module Planka
  # The full state of one card as a single JSON-able document: description,
  # board and list identity, labels, members, named task lists with their
  # tasks, linked blockers and comments. Reads GET /api/cards/:id (which omits
  # label and list names) and resolves those names from the card's board.
  #
  # client answers #card(id), #comments(id) and #board(id).
  class CardDetail
    def initialize(client, base_url: ENV.fetch("PLANKA_BASE_URL"))
      @client = client
      @base_url = base_url.sub(%r{/+\z}, "")
    end

    def for(card_id)
      response = @client.card(card_id)
      item = response.fetch("item")
      included = response.fetch("included")
      board = board_for(item["boardId"])

      {
        "id" => item.fetch("id"),
        "name" => item["name"],
        "description" => item["description"],
        "type" => item["type"],
        "boardId" => item["boardId"],
        "listId" => item["listId"],
        "listName" => board&.list_name(item["listId"]),
        "position" => item["position"],
        "url" => "#{@base_url}/cards/#{item.fetch("id")}",
        "labels" => labels(included, board),
        "members" => members(included),
        "taskLists" => task_lists(included),
        "blockers" => blockers(included),
        "comments" => comments(card_id),
      }
    end

    private

    def board_for(board_id) = board_id && Board.new(@client.board(board_id), base_url: @base_url)

    def labels(included, board)
      Array(included["cardLabels"]).map do |cl|
        { "id" => cl["labelId"], "name" => board&.label_name(cl["labelId"]) }
      end
    end

    def members(included) = Array(included["cardMemberships"]).map { |m| m["userId"] }

    def task_lists(included)
      tasks = Array(included["tasks"])
      Array(included["taskLists"]).sort_by { |tl| tl["position"].to_f }.map do |tl|
        {
          "id" => tl["id"],
          "name" => tl["name"],
          "position" => tl["position"],
          "tasks" => tasks.select { |t| t["taskListId"] == tl["id"] }
            .sort_by { |t| t["position"].to_f }
            .map { |t| t.slice("id", "name", "isCompleted", "linkedCardId", "position") },
        }
      end
    end

    # Blocking edges are tasks linked to the blocker cards; Planka marks one
    # complete when its card closes.
    def blockers(included)
      Array(included["tasks"]).select { |t| t["linkedCardId"] }.map do |t|
        { "cardId" => t["linkedCardId"], "taskId" => t["id"], "completed" => t["isCompleted"] }
      end
    end

    def comments(card_id)
      @client.comments(card_id).map { |c| c.slice("id", "text", "userId", "createdAt") }
    end
  end
end
