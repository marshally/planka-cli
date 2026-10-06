module Planka
  # Creates a column (list) on a board, appended after the board's existing
  # columns. Planka's kanban columns are "active" or "closed"; the archive and
  # trash lists are system lists and are ignored when appending.
  #
  # client answers #board and #create_list.
  class Lists
    TYPES = %w[active closed].freeze

    def initialize(client)
      @client = client
    end

    def create(board_id:, name:, type: "active", position: nil)
      raise Error, "type must be one of #{TYPES.join(", ")}" unless TYPES.include?(type)

      position ||= Position.after(columns(board_id))
      list = @client.create_list(board_id, name:, type:, position:)
      { "list" => list.slice("id", "boardId", "name", "type", "position"), "created" => true }
    end

    private

    def columns(board_id) = Array(@client.board(board_id)["lists"]).select { |list| TYPES.include?(list["type"]) }
  end
end
