require_relative "planka_test_helper"

class Planka::TaskListsTest < Minitest::Test
  # Stands in for Client: serves a card's existing task lists and records writes.
  class FakeClient
    attr_reader :writes

    def initialize(task_lists: [])
      @task_lists = task_lists
      @writes = []
    end

    def card(_id) = { "included" => { "taskLists" => @task_lists } }

    def create_task_list(card_id, **attrs)
      @writes << [ :create_task_list, card_id, attrs ]
      { "id" => "list-new", "cardId" => card_id, "name" => attrs[:name], "position" => attrs[:position] }
    end

    def update_task_list(task_list_id, **attrs)
      @writes << [ :update_task_list, task_list_id, attrs ]
      { "id" => task_list_id, "cardId" => "C", "name" => attrs[:name], "position" => 65_536 }
    end
  end

  def task_lists(client) = Planka::TaskLists.new(client)

  def test_create_appends_below_existing_lists
    client = FakeClient.new(task_lists: [ { "id" => "a", "name" => "Blocked by", "position" => 65_536 } ])

    result = task_lists(client).create(card_id: "C", name: "Acceptance criteria")

    assert result["created"]
    assert_equal [ [ :create_task_list, "C", { name: "Acceptance criteria", position: 131_072, showOnFrontOfCard: false } ] ], client.writes
    assert_equal "Acceptance criteria", result["taskList"]["name"]
  end

  def test_create_honours_an_explicit_position
    client = FakeClient.new

    task_lists(client).create(card_id: "C", name: "Notes", position: 42)

    assert_equal 42, client.writes.first[2][:position]
  end

  def test_rename_updates_by_id
    client = FakeClient.new

    result = task_lists(client).rename(task_list_id: "tl-1", name: "Acceptance criteria")

    assert_equal [ [ :update_task_list, "tl-1", { name: "Acceptance criteria" } ] ], client.writes
    assert_equal "Acceptance criteria", result["taskList"]["name"]
    assert result["renamed"]
  end
end
