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

  def test_unknown_and_ambiguous_task_references_use_the_shared_reference_failures
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    2.times { |i| @server.tasks << { "id" => "70#{i}", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => i } }
    out, err, status = planka("update", "task", "Missing", "--card", CARD, "--completed", "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal({ "code" => "not_found", "message" => "Task not found on the card" }, JSON.parse(out)["error"])
    out, err, status = planka("update", "task", "Verify", "--card", CARD, "--completed", "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_equal "Ambiguous task name; candidate IDs: 700, 701", JSON.parse(out).dig("error", "message")
  end

  def test_unknown_task_writes_require_readback_and_rejected_writes_keep_the_task
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    @server.tasks << { "id" => "700", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => 1 }
    @server.inject("PATCH", %r{/api/tasks/700$}, :apply_then_drop)
    out, err, status = planka("update", "task", "700", "--card", CARD, "--completed", "-o", "json")
    doc = JSON.parse(out)
    assert_equal 1, status.exitstatus, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "isCompleted")
    assert_equal "readback-task", doc.dig("error", "recovery", "action")
    assert_equal 1, @server.counts("PATCH", %r{/api/tasks/700$})
    @server.tasks.first["isCompleted"] = false
    @server.inject("PATCH", %r{/api/tasks/700$}, 403)
    out, err, status = planka("update", "task", "700", "--card", CARD, "--completed", "-o", "json")
    doc = JSON.parse(out)
    assert_equal 1, status.exitstatus, err
    assert_equal "authorization_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_equal({ "id" => "700", "name" => "Verify", "taskListId" => "600", "isCompleted" => false, "cardId" => CARD }, doc["data"])
  end
end
