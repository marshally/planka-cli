require_relative "planka_test_helper"

class Planka::BlockingTest < Minitest::Test
  # Stands in for Planka::Client: serves one card's task lists and tasks, and
  # records the writes Blocking asks for.
  class FakeClient
    attr_reader :writes

    def initialize(task_lists: [], tasks: [])
      @task_lists = task_lists
      @tasks = tasks
      @writes = []
    end

    def card(_id) = { "included" => { "taskLists" => @task_lists, "tasks" => @tasks } }

    def create_task_list(card_id, **attrs)
      @writes << [ :create_task_list, card_id, attrs ]
      { "id" => "new-list", "name" => attrs[:name], "position" => attrs[:position] }
    end

    def create_task(task_list_id, **attrs)
      @writes << [ :create_task, task_list_id, attrs ]
      { "id" => "task-#{@writes.size}", "isCompleted" => attrs[:linkedCardId] == "closed-card" }.merge(attrs.transform_keys(&:to_s))
    end
  end

  def link(client, blockers) = Planka::Workflow::Blocking.new(client).link("10", blockers)

  def test_creates_the_blocked_by_list_after_existing_lists
    client = FakeClient.new(task_lists: [ { "id" => "ac", "name" => "Acceptance criteria", "position" => 65_536 } ])

    link(client, [ "1" ])

    assert_equal [ :create_task_list, "10", { name: "Blocked by", position: 131_072, showOnFrontOfCard: true } ], client.writes.first
  end

  def test_links_each_blocker_once_in_order
    client = FakeClient.new

    assert_equal [ "linked: 1 (open)", "linked: 2 (open)" ], link(client, [ "1", "2", "1" ])
    assert_equal [ [ :create_task, "new-list", { linkedCardId: "1", position: 65_536 } ],
                   [ :create_task, "new-list", { linkedCardId: "2", position: 131_072 } ] ], client.writes.drop(1)
  end

  def test_reuses_the_existing_list_and_skips_blockers_already_linked
    client = FakeClient.new(
      task_lists: [ { "id" => "bb", "name" => "Blocked by", "position" => 65_536 } ],
      tasks: [ { "id" => "t1", "taskListId" => "bb", "linkedCardId" => "1", "position" => 65_536 } ]
    )

    assert_equal [ "already linked: 1", "linked: 2 (open)" ], link(client, [ "1", "2" ])
    assert_equal [ [ :create_task, "bb", { linkedCardId: "2", position: 131_072 } ] ], client.writes
  end

  def test_reports_a_blocker_that_is_already_closed
    assert_equal [ "linked: closed-card (closed)" ], link(FakeClient.new, [ "closed-card" ])
  end

  def test_a_card_cannot_block_itself
    error = assert_raises(Planka::Error) { link(FakeClient.new, [ "10" ]) }

    assert_equal "a card cannot block itself", error.message
  end

  def test_card_id_accepts_ids_and_card_urls
    assert_equal "1870510968568546410", Planka.card_id("1870510968568546410")
    assert_equal "1870510968568546410", Planka.card_id("https://planka.home.yountlabs.com/cards/1870510968568546410/")
  end

  def test_card_id_rejects_anything_else
    error = assert_raises(Planka::Error) { Planka.card_id("Contract edits") }

    assert_equal "not a card id or URL: Contract edits", error.message
  end
end
