require_relative "label_relationship_cli_test"

class Planka::TaskCompletionCLITest < Planka::LabelRelationshipCLITest
  def test_completes_and_reopens_an_ordinary_task_but_refuses_linked_tasks
    list = { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    @server.task_lists << list
    @server.tasks << { "id" => "700", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => 1 }
    out, err, status = planka("update", "task", "Verify", "--card", CARD, "--completed", "-o", "json")
    assert status.success?, err
    assert_equal true, JSON.parse(out).dig("data", "isCompleted")
    out, err, status = planka("update", "task", "700", "--card", CARD, "--no-completed", "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("data", "isCompleted")
    @server.tasks.first["linkedCardId"] = "999"
    out, _, status = planka("update", "task", "700", "--card", CARD, "--completed", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "linked_task", JSON.parse(out).dig("error", "code")
  end
end
