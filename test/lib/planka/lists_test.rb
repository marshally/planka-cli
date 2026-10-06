require_relative "planka_test_helper"

class Planka::ListsTest < Minitest::Test
  # Stands in for Client: serves a board's lists and records creates.
  class FakeClient
    attr_reader :writes

    def initialize(lists: [])
      @lists = lists
      @writes = []
    end

    def board(_id) = { "lists" => @lists }

    def create_list(board_id, **attrs)
      @writes << [:create_list, board_id, attrs]
      { "id" => "list-new", "boardId" => board_id, "name" => attrs[:name], "type" => attrs[:type], "position" => attrs[:position] }
    end
  end

  def lists(client) = Planka::Lists.new(client)

  def test_create_appends_after_existing_columns_ignoring_archive_and_trash
    client = FakeClient.new(lists: [
                              { "id" => "a", "type" => "active", "position" => 65_536 },
                              { "id" => "b", "type" => "closed", "position" => 131_072 },
                              { "id" => "arch", "type" => "archive", "position" => 999_999 },
                            ])

    result = lists(client).create(board_id: "B", name: "done", type: "closed")

    assert result["created"]
    assert_equal [[:create_list, "B", { name: "done", type: "closed", position: 196_608 }]], client.writes
  end

  def test_create_on_a_board_with_no_columns_starts_at_the_first_position
    client = FakeClient.new(lists: [{ "id" => "trash", "type" => "trash", "position" => 0 }])

    lists(client).create(board_id: "B", name: "ready-for-agent")

    assert_equal({ name: "ready-for-agent", type: "active", position: 65_536 }, client.writes.first[2])
  end

  def test_create_honours_an_explicit_position
    client = FakeClient.new

    lists(client).create(board_id: "B", name: "triage", position: 10)

    assert_equal 10, client.writes.first[2][:position]
  end

  def test_create_rejects_an_unknown_type
    error = assert_raises(Planka::Error) { lists(FakeClient.new).create(board_id: "B", name: "x", type: "bogus") }

    assert_includes error.message, "type must be one of"
  end
end
