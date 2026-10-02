module Planka
  # Creates a column (list) on a board, appended after the board's existing
  # columns. Planka's kanban columns are "active" or "closed"; the archive and
  # trash lists are system lists and are ignored when appending.
  #
  # client answers #board and #create_list.
  class Lists
    POSITION_GAP = 65_536
    TYPES = %w[active closed].freeze

    def initialize(client)
      @client = client
    end

    def create(board_id:, name:, type: "active", position: nil)
      raise Error, "type must be one of #{TYPES.join(", ")}" unless TYPES.include?(type)

      position ||= next_position(Array(@client.board(board_id)["lists"]))
      list = @client.create_list(board_id, name:, type:, position:)
      { "list" => list.slice("id", "boardId", "name", "type", "position"), "created" => true }
    end

    private

    def next_position(lists)
      positions = lists.select { |list| TYPES.include?(list["type"]) }.map { |list| list["position"].to_f }
      (positions.max || 0) + POSITION_GAP
    end
  end
end
