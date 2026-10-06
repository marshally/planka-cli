module Planka
  module Cards
    # The full state of one card as a single JSON-able document: description,
    # board and list identity, labels, members, named task lists with their
    # tasks, linked blockers and comments. Reads GET /api/cards/:id (which omits
    # label and list names) and resolves those names from the card's board.
    #
    # client answers #card(id), #comments(id) and #board(id).
    class Detail
      def self.read(client, id, base_url:)
        new(client, base_url: base_url, validate: true).for(id)
      end

      def initialize(client, base_url: ENV.fetch("PLANKA_BASE_URL"), validate: false)
        @validate = validate
        @client = client
        @base_url = base_url.sub(%r{/+\z}, "")
      end

      def for(card_id)
        response = @client.card(card_id)
        validate_response!(response) if @validate
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

      def board_for(board_id)
        return unless board_id

        included = @client.board(board_id)
        Boards::Snapshot.validate!(included) if @validate
        Board.new(included, base_url: @base_url)
      rescue KeyError
        raise InvalidResponse, "Invalid related board records" if @validate

        raise
      end

      def validate_response!(response)
        unless response.is_a?(Hash) && response["item"].is_a?(Hash) &&
               response["item"]["id"].is_a?(String) && !response["item"]["id"].empty? && response["included"].is_a?(Hash)
          raise InvalidResponse, "Invalid card response"
        end

        description = response["item"]["description"]
        unless description.nil? || description.is_a?(String)
          raise InvalidResponse, "Invalid card description"
        end

        %w[cardLabels cardMemberships taskLists tasks].each do |key|
          records = response["included"][key]
          unless records.nil? || (records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) })
            raise InvalidResponse, "Invalid card related records"
          end
        end
        %w[taskLists tasks].each do |key|
          Array(response["included"][key]).each do |record|
            position = record["position"]
            unless position.nil? || position.is_a?(Numeric) || position.is_a?(String)
              raise InvalidResponse, "Invalid task position"
            end
          end
        end
      end

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
        records = @client.comments(card_id)
        if @validate && (!records.is_a?(Array) || !records.all? { |record| record.is_a?(Hash) })
          raise InvalidResponse, "Invalid comment records"
        end

        records.map { |c| c.slice("id", "text", "userId", "createdAt") }
      end
    end
  end
end
