require "minitest/autorun"
require "planka"
require_relative "fake_planka"

class CardTasksResourceTest < Minitest::Test
  CARD = FakePlanka::PARENT_CARD

  def setup
    @server = FakePlanka.new
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    @server.tasks << { "id" => "700", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => 1 }
  end

  def teardown = @server.stop

  def with_tasks
    Planka::Client.session(base_url: @server.base_url, email: "bot@example.com", password: "fixture", validate_responses: true) do |client|
      yield Planka::Cards::Tasks.new(client, card_id: CARD)
    end
  end

  def test_update_completes_and_reopens_a_task_and_skips_an_already_satisfied_update
    with_tasks do |tasks|
      completed = tasks.update("700", completed: true)
      assert_equal true, completed.changed
      assert_equal({ "id" => "700", "taskListId" => "600", "name" => "Verify", "cardId" => CARD, "isCompleted" => true }, completed.data)
      assert_equal false, tasks.update("Verify", completed: true).changed
      reopened = tasks.update("700", completed: false)
      assert_equal true, reopened.changed
      assert_equal false, reopened.data.fetch("isCompleted")
    end
  end

  def test_update_rejects_a_non_boolean_completion_before_changing_the_task
    with_tasks do |tasks|
      assert_raises(ArgumentError) { tasks.update("700", completed: "false") }
      assert_equal false, tasks.update("700", completed: false).changed
    end
  end
end
