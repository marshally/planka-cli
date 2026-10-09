require_relative "fake_planka"

# Project/board endpoints from Community v2.2.1, sharing the existing session
# and fault-injection HTTP fixture. Legacy snapshot fixtures remain unchanged.
class FakeProjectBoards < FakePlanka
  PROJECT_ID = "600000000000000001".freeze
  OTHER_PROJECT = "600000000000000002".freeze

  def initialize(**options)
    super
    @boards = [board_record(BOARD_ID, "Development", 65_536)]
  end

  def add_project_board(id, name, position:, project_id: PROJECT_ID)
    @boards << board_record(id, name, position, project_id)
  end

  private

  def board_record(id, name, position, project_id = PROJECT_ID)
    { "id" => id, "projectId" => project_id, "name" => name, "position" => position,
      "createdAt" => "2026-10-01T00:00:00.000Z", "updatedAt" => nil }
  end

  def route(method, path, body)
    case [method, path.split("/").reject(&:empty?)]
    in ["DELETE", ["api", "boards", id]]
      board = @boards.find { |record| record["id"] == id }
      @boards.delete(board)
      board ? [200, { "item" => board }] : [404, {}]
    in ["PATCH", ["api", "boards", id]]
      board = @boards.find { |record| record["id"] == id }
      board ? [200, { "item" => board.merge!(JSON.parse(body)) }] : [404, {}]
    in ["POST", ["api", "projects", id, "boards"]]
      data = JSON.parse(body)
      board = board_record(next_id, data.fetch("name"), data.fetch("position"), id)
      @boards << board
      [200, { "item" => board, "included" => { "boardMemberships" => [] } }]
    in ["GET", ["api", "boards", id]]
      record = @boards.find { |board| board["id"] == id }
      record ? [200, board_payload(id).merge("item" => record)] : [404, {}]
    in ["GET", ["api", "projects", id]]
      return [404, {}] unless [PROJECT_ID, OTHER_PROJECT].include?(id)

      [200, { "item" => { "id" => id, "name" => "Project" },
              "included" => { "boards" => @boards.select { |board| board["projectId"] == id } } }]
    else super
    end
  end
end
