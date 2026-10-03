module Planka
  # Read-only workflow inspection using the same acceptance-criteria rule as unticked.
  class PendingCriteria
    def self.read(client, id, base_url:)
      response = client.card(id)
      board_id = response.is_a?(Hash) && response["item"].is_a?(Hash) && response["item"]["boardId"]
      unless board_id.is_a?(String) && board_id.match?(/\A\d+\z/)
        raise InvalidResponse, "Invalid card board reference"
      end
      included = client.board(board_id)
      Snapshot.validate!(included)
      validate_criteria!(included)
      board = Board.new(included, base_url: base_url)
      { "cardId" => id, "criteria" => board.card(id).unticked_criteria }
    rescue KeyError
      raise InvalidResponse, "Invalid criteria board records"
    end

    def self.validate_criteria!(included)
      included.fetch("taskLists").each do |list|
        unless %w[id cardId name].all? { |key| list[key].is_a?(String) }
          raise InvalidResponse, "Invalid criteria task list"
        end
      end
      included.fetch("tasks").each do |task|
        unless task["taskListId"].is_a?(String) && task["name"].is_a?(String) &&
            [true, false].include?(task["isCompleted"])
          raise InvalidResponse, "Invalid criteria task"
        end
      end
    end
    private_class_method :validate_criteria!
  end
end
