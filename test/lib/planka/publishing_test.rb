require_relative "planka_test_helper"

class Planka::PublishingTest < Minitest::Test
  # Stands in for Client: records writes and serves the card's task lists and
  # tasks for the reconciliation read inside create and resume. A task create
  # can be made to fail, to exercise partial failure.
  class FakeClient
    attr_reader :writes

    def initialize(task_lists: [], tasks: [], fail_task_on: nil)
      @task_lists = task_lists
      @tasks = tasks
      @fail_task_on = fail_task_on
      @writes = []
      @created_tasks = 0
    end

    def create_card(list_id, **attrs)
      @writes << [ :create_card, list_id, attrs ]
      { "id" => "card-new", "name" => attrs[:name] }
    end

    def card(_id) = { "item" => { "id" => "card-new", "name" => "Resumed" }, "included" => { "taskLists" => @task_lists, "tasks" => @tasks } }

    def create_task_list(card_id, **attrs)
      @writes << [ :create_task_list, card_id, attrs ]
      list = { "id" => "list-new", "name" => attrs[:name], "position" => attrs[:position] }
      @task_lists << list
      list
    end

    def create_task(task_list_id, **attrs)
      @created_tasks += 1
      raise Planka::Error, "boom" if @created_tasks == @fail_task_on

      @writes << [ :create_task, task_list_id, attrs ]
      task = { "id" => "task-#{@created_tasks}", "taskListId" => task_list_id, "name" => attrs[:name], "isCompleted" => false, "position" => attrs[:position] }
      @tasks << task
      task
    end
  end

  def publishing(client) = Planka::Publishing.new(client, base_url: "https://planka.test///")

  def test_create_spec_makes_a_project_card_with_no_criteria
    client = FakeClient.new

    result = publishing(client).create_spec(list_id: "L", name: "Spec", description: "Body", position: 99)

    assert_equal [ [ :create_card, "L", { name: "Spec", description: "Body", type: "project", position: 99 } ] ], client.writes
    assert_equal "https://planka.test/cards/card-new", result["card"]["url"]
  end

  def test_create_ticket_adds_one_named_criteria_list_and_a_task_per_criterion
    client = FakeClient.new

    result = publishing(client).create_ticket(list_id: "L", name: "T", description: "D", criteria: [ "a", "b" ], position: 5)

    assert_equal [ :create_card, :create_task_list, :create_task, :create_task ], client.writes.map(&:first)
    assert_equal "Acceptance criteria", client.writes[1][2][:name]
    assert_equal true, client.writes[1][2][:showOnFrontOfCard]
    assert_equal [ 65_536, 131_072 ], client.writes.last(2).map { |w| w[2][:position] }
    assert_equal [ "a", "b" ], result["tasks"].map { |t| t["name"] }
    assert_equal [ false, false ], result["tasks"].map { |t| t["reused"] }
    assert result["completed"]
  end

  def test_resume_reuses_the_existing_list_and_adds_only_missing_criteria
    client = FakeClient.new(
      task_lists: [ { "id" => "ac", "name" => "Acceptance criteria", "position" => 65_536 } ],
      tasks: [ { "id" => "t1", "taskListId" => "ac", "name" => "a", "isCompleted" => false, "position" => 65_536 } ]
    )

    result = publishing(client).resume_ticket(card_id: "card-new", criteria: [ "a", "b" ])

    assert_equal [ [ :create_task, "ac", { name: "b", position: 131_072 } ] ], client.writes
    assert_equal [ "a", "b" ], result["tasks"].map { |t| t["name"] }
    assert_equal [ true, false ], result["tasks"].map { |t| t["reused"] }
    assert result["completed"]
  end

  def test_a_second_criteria_list_is_rejected
    client = FakeClient.new(task_lists: [
      { "id" => "ac1", "name" => "Acceptance criteria", "position" => 1 },
      { "id" => "ac2", "name" => "Acceptance criteria", "position" => 2 },
    ])

    error = assert_raises(Planka::Error) { publishing(client).resume_ticket(card_id: "card-new", criteria: [ "a" ]) }

    assert_includes error.message, "Acceptance criteria lists"
  end

  def test_a_blank_description_is_omitted_not_sent_as_empty_string
    [ nil, "" ].each do |blank|
      client = FakeClient.new
      publishing(client).create_spec(list_id: "L", name: "S", description: blank)

      refute client.writes.first[2].key?(:description), "description #{blank.inspect} should be omitted"
    end
  end

  def test_a_failed_task_create_raises_partial_failure_carrying_the_ids_so_far
    client = FakeClient.new(fail_task_on: 2)

    error = assert_raises(Planka::PartialFailure) do
      publishing(client).create_ticket(list_id: "L", name: "T", description: "D", criteria: [ "a", "b" ], position: 1)
    end

    assert_equal "card-new", error.state.dig("card", "id")
    assert_equal "list-new", error.state.dig("taskList", "id")
    assert_equal [ "a" ], error.state["tasks"].map { |t| t["name"] }
    refute error.state["completed"]
  end
end
