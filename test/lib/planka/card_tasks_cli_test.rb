require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class CardTasksCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {})
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fixture", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
  end

  def ordinary_task
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    @server.tasks << { "id" => "700", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => 1 }
  end

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

  def test_tasks_use_the_shared_card_scope_help_and_output
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Any tasks", "position" => 1 }
    @server.tasks << { "id" => "700", "taskListId" => "600", "name" => "Verify", "isCompleted" => false, "linkedCardId" => nil, "position" => 1 }
    name = @server.find_card(CARD).fetch("name")
    out, err, status = planka("update", "task", "Verify", "--card", name, "--board", @server.board_id, "--completed")
    assert status.success?, err
    assert_equal "Verify (700) on card #{CARD}\ncompleted: true\n", out
    out, err, status = planka("update", "task", "Verify", "--card", name, "--completed", "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_equal "Card names require --board or PLANKA_BOARD_ID", JSON.parse(out).dig("error", "message")
    out, err, status = planka("update", "--help")
    assert status.success?, err
    assert_includes out, "usage: planka update <resource> REF --card CARD [flags]"
    assert_match(/^  task TASK --card CARD  /, out)
  end

  def test_a_malformed_write_response_is_an_unknown_outcome
    ordinary_task
    @server.inject("PATCH", %r{/api/tasks/700$}, { "item" => { "id" => "700", "taskListId" => "999", "isCompleted" => true } })
    out, err, status = planka("update", "task", "700", "--card", CARD, "--completed", "-o", "json")
    doc = JSON.parse(out)
    assert_equal 1, status.exitstatus, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_equal "readback-task", doc.dig("error", "recovery", "action")
  end

  def test_card_and_completion_flags_are_required_before_any_request
    [[["update", "task", "700", "--completed"], "Exactly one --card is required"],
     [["update", "task", "700", "--card", CARD], "Exactly one --completed or --no-completed is required"]].each do |args, message|
      out, err, status = planka(*args, "-o", "json")
      assert_equal 2, status.exitstatus, err
      assert_equal({ "code" => "invalid_input", "message" => message }, JSON.parse(out)["error"])
    end
    assert_empty @server.requests
  end

  def test_leaf_help_needs_no_credentials_or_network
    [["update", "task", "--help"], ["update", "tasks", "--help"]].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil })
      assert status.success?, err
      assert_includes out, "usage: planka update task TASK --card CARD [--board BOARD] --completed|--no-completed [-o human|json]"
    end
    assert_empty @server.requests
  end
end
