require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class TasksCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD

  def setup
    @server = FakePlanka.new
    @server.task_lists << { "id" => "600", "cardId" => CARD, "name" => "Checks", "position" => 2 }
    @server.task_lists << { "id" => "601", "cardId" => CARD, "name" => "First", "position" => 1 }
    @server.tasks << task("700", "600", "Verify", 2)
    @server.tasks << task("701", "600", "Verify", 1, "isCompleted" => true, "assigneeUserId" => "900")
    @server.tasks << task("702", "601", "Linked", 1, "linkedCardId" => "999")
  end

  def teardown = @server.stop

  def task(id, list, name, position, attrs = {})
    { "id" => id, "taskListId" => list, "name" => name, "position" => position,
      "isCompleted" => false, "assigneeUserId" => nil, "linkedCardId" => nil,
      "createdAt" => nil, "updatedAt" => nil }.merge(attrs)
  end

  def planka(*args, env: {})
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fixture", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status]
  end

  def test_collection_orders_flat_tasks_filters_before_limit_and_performs_no_resource_writes
    doc, err, status = json("get", "tasks", "--card", CARD)
    assert status.success?, err
    assert_equal(%w[702 701 700], doc["data"].map { |t| t["id"] })
    assert_equal({ "complete" => true }, doc["meta"])
    assert_equal task("702", "601", "Linked", 1, "linkedCardId" => "999").merge("cardId" => CARD), doc["data"].first
    doc, err, status = json("get", "tasks", "--task-list", "600", "--name", "Verify", "--completed", "false", "--limit", "1")
    assert status.success?, err
    assert_equal(["700"], doc["data"].map { |t| t["id"] })
    assert_equal true, doc.dig("meta", "complete")
    assert_empty(@server.requests.select { |m, p, _| m != "GET" && !p.start_with?("/api/access-tokens") })
    assert_equal 2, @server.counts("DELETE", %r{/api/access-tokens/me$})
  end

  def test_create_ordinary_and_linked_tasks_then_read_them_without_workflow_writes
    doc, err, status = json("create", "task", "--task-list", "600", "--name", "New check", "--completed", "true")
    assert status.success?, err
    created = doc["data"]
    assert_equal true, doc.dig("meta", "changed")
    assert_equal "New check", created["name"]
    assert_equal 65538, created["position"]
    assert_equal true, created["isCompleted"]
    read, err, status = json("get", "task", created["id"])
    assert status.success?, err
    assert_equal created, read["data"]
    doc, err, status = json("create", "tasks", "--task-list", "Checks", "--card", CARD, "--linked-card", CARD, "--position", "0")
    assert status.success?, err
    assert_equal @server.find_card(CARD)["name"], doc.dig("data", "name")
    assert_equal CARD, doc.dig("data", "linkedCardId")
    writes = @server.requests.select { |m, p, _| m != "GET" && !p.start_with?("/api/access-tokens") }
    assert_equal ["POST", "POST"], writes.map(&:first)
    assert_equal({ "name" => "New check", "isCompleted" => true, "position" => 65538 }, JSON.parse(writes.first.last))
    assert_equal({ "linkedCardId" => CARD, "position" => 0 }, JSON.parse(writes.last.last))
  end

  def test_update_supplied_fields_board_assignee_and_noop_then_clear
    @server.users << { "id" => "900", "name" => "Alex", "username" => "alex", "email" => "private" }
    @server.board_memberships << { "id" => "910", "boardId" => @server.board_id, "userId" => "900" }
    doc, err, status = json("update", "task", "700", "--name", "Checked", "--position", "3.5", "--completed", "true", "--assignee", "Alex")
    assert status.success?, err
    assert_equal true, doc.dig("meta", "changed")
    assert_equal "900", doc.dig("data", "assigneeUserId")
    writes = @server.requests.select { |m, p, _| m == "PATCH" && p == "/api/tasks/700" }
    assert_equal({ "name" => "Checked", "position" => 3.5, "isCompleted" => true, "assigneeUserId" => "900" }, JSON.parse(writes.first.last))
    doc, err, status = json("update", "tasks", "Checked", "--card", CARD, "--completed", "true")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_equal 1, @server.counts("PATCH", %r{/api/tasks/700$})
    doc, err, status = json("update", "task", "700", "--clear-assignee")
    assert status.success?, err
    assert_nil doc.dig("data", "assigneeUserId")
    assert_equal({ "assigneeUserId" => nil }, JSON.parse(@server.requests.select { |m, p, _| m == "PATCH" && p == "/api/tasks/700" }.last.last))
    assert_equal "Linked", @server.tasks.find { |t| t["id"] == "702" }["name"]
    doc, err, status = json("update", "task", "702", "--position", "5")
    assert status.success?, err
    assert_equal "999", doc.dig("data", "linkedCardId")
  end

  def test_move_preserves_identity_and_fields_and_delete_preserves_linked_card_and_parents
    doc, err, status = json("move", "task", "701", "--task-list", "601")
    assert status.success?, err
    assert_equal "601", doc.dig("data", "taskListId")
    assert_equal 65537, doc.dig("data", "position")
    assert_equal "900", doc.dig("data", "assigneeUserId")
    assert_equal true, doc.dig("data", "isCompleted")
    doc, err, status = json("move", "tasks", "701", "--task-list", "First", "--card", CARD)
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_equal 1, @server.counts("PATCH", %r{/api/tasks/701$})
    doc, err, status = json("delete", "task", "702")
    assert status.success?, err
    assert_equal true, doc.dig("data", "deleted")
    assert_equal "999", doc.dig("data", "linkedCardId")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal(%w[600 601], @server.task_lists.map { |list| list["id"] })
    assert @server.find_card(CARD)
    assert_equal(%w[700 701], @server.tasks.map { |task| task["id"] })
    assert_equal 1, @server.counts("DELETE", %r{/api/tasks/702$})
  end

  def test_assignee_and_linked_card_filters_use_and_matching_and_resolve_names_in_the_board
    @server.users << { "id" => "900", "name" => "Alex" }
    @server.board_memberships << { "id" => "910", "boardId" => @server.board_id, "userId" => "900" }
    @server.tasks.find { |t| t["id"] == "701" }["linkedCardId"] = CARD
    doc, err, status = json("get", "tasks", "--card", CARD, "--assignee", "Alex", "--linked-card", @server.find_card(CARD)["name"], "--name", "Verify", "--completed", "true", "--limit", "1")
    assert status.success?, err
    assert_equal(["701"], doc["data"].map { |t| t["id"] })
    doc, err, status = json("get", "tasks", "--card", CARD, "--linked-card", "999")
    assert status.success?, err
    assert_equal(["702"], doc["data"].map { |t| t["id"] })
    doc, err, status = json("get", "tasks", "--card", CARD, "--limit", "1")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "complete")
    assert_equal(["702"], doc["data"].map { |t| t["id"] })
  end

  def test_native_api_references_are_same_instance_and_explicit_parent_agreement_is_enforced
    doc, err, status = json("get", "task", "#{@server.base_url}/api/tasks/700", "--card", CARD)
    assert status.success?, err
    assert_equal "700", doc.dig("data", "id")
    doc, err, status = json("get", "tasks", "--task-list", "#{@server.base_url}/api/task-lists/600")
    assert status.success?, err
    assert_equal(%w[701 700], doc["data"].map { |t| t["id"] })
    doc, _, status = json("get", "task", "700", "--card", CARD, "--board", "123")
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", doc.dig("error", "code")
    requests = @server.requests.size
    _, _, status = json("get", "task", "https://foreign.example/api/tasks/700")
    assert_equal 2, status.exitstatus
    assert_equal requests, @server.requests.size
  end

  def test_local_conflicts_and_bad_configuration_make_no_requests
    commands = [
      %w[get tasks], ["get", "tasks", "--card", CARD, "--task-list", "600"],
      %w[create task --task-list 600], %w[create task --task-list 600 --name X --linked-card 123],
      %w[create task --task-list 600 --linked-card 123 --completed false],
      %w[create task --task-list 600 --name X --assignee 900],
      %w[update task 700], %w[update task 700 --completed maybe],
      %w[update task 700 --assignee 900 --clear-assignee], %w[update task 700 --completed false --no-completed],
      %w[update task 700 --task-list 600 --name X], %w[update task 700 --linked-card 123],
      %w[update task 700 --position NaN], %w[update task 700 --position Infinity], %w[update task 700 --position -1],
      %w[move task 700], %w[get tasks --task-list Checks],
      ["create", "task", "--task-list", "600", "--name", " "],
      ["create", "task", "--task-list", "600", "--name", "x" * 1025],
      ["get", "tasks", "--card", CARD, "--limit", "0"],
      ["get", "task", "700", "--card", CARD, "--name", "Verify"],
      ["get", "tasks", "--card", CARD, "--name", "A", "--name", "B"],
      ["get", "tasks", "--card", CARD, "--label", "123"],
      ["get", "tasks", "--card", CARD, "--completed"]
    ]
    commands.each do |args|
      doc, err, status = json(*args)
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code")
    end
    doc, _, status = json("get", "tasks", "--card", CARD, env: { "PLANKA_AGENT_PASSWORD" => "" })
    assert_equal 1, status.exitstatus
    assert_equal "configuration_error", doc.dig("error", "code")
    assert_empty @server.requests
  end

  def test_linked_field_changes_foreign_links_moves_and_nonmember_assignees_are_rejected_without_writes
    @server.cards << @server.find_card(CARD).merge("id" => "999", "boardId" => "123", "name" => "Foreign")
    @server.task_lists << { "id" => "602", "cardId" => "999", "name" => "Foreign", "position" => 1 }
    @server.users << { "id" => "900", "name" => "Alex" }
    [
      %w[update task 702 --name Changed], %w[update task 702 --completed false],
      %w[update task 702 --clear-assignee], %w[update task 702 --assignee 900],
      %w[update task 700 --assignee 900], %w[move task 700 --task-list 602],
      %w[create task --task-list 600 --linked-card 999]
    ].each do |args|
      doc, err, status = json(*args)
      refute status.success?, "#{args.inspect}: #{err}"
      refute_nil doc["error"]
    end
    assert_empty(@server.requests.select { |method, path, _| method != "GET" && !path.start_with?("/api/access-tokens") })
  end

  def test_malformed_collection_preserves_matching_partial_data_and_cleanup
    @server.tasks << task("703", "600", "Bad", 3, "isCompleted" => "false")
    doc, err, status = json("get", "tasks", "--task-list", "600", "--completed", "true")
    assert_equal 1, status.exitstatus, err
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "complete")
    assert_equal(["701"], doc["data"].map { |t| t["id"] })
    assert_equal 1, @server.counts("DELETE", %r{/api/access-tokens/me$})
  end

  def test_uncertain_create_update_move_and_delete_preserve_recovery_and_never_retry_writes
    cases = [
      [["create", "task", "--task-list", "600", "--name", "Unknown"], "POST", %r{/api/task-lists/600/tasks$}],
      [["update", "task", "700", "--completed", "true"], "PATCH", %r{/api/tasks/700$}],
      [["move", "task", "701", "--task-list", "601"], "PATCH", %r{/api/tasks/701$}],
      [["delete", "task", "702"], "DELETE", %r{/api/tasks/702$}],
    ]
    cases.each do |args, method, path|
      @server.inject(method, path, :apply_then_drop)
      doc, err, status = json(*args)
      assert_equal 1, status.exitstatus, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_equal "readback-task", doc.dig("error", "recovery", "action")
      assert_equal 1, @server.counts(method, path)
      assert_equal CARD, doc.dig("data", "cardId")
    end
    assert_equal 4, @server.counts("DELETE", %r{/api/access-tokens/me$})
  end

  def test_malformed_write_responses_are_unknown_and_http_rejections_preserve_known_data
    [
      [["create", "task", "--task-list", "600", "--name", "X"], "POST", %r{/api/task-lists/600/tasks$}],
      [["update", "task", "700", "--name", "X"], "PATCH", %r{/api/tasks/700$}],
      [["move", "task", "700", "--task-list", "601"], "PATCH", %r{/api/tasks/700$}],
      [["delete", "task", "700"], "DELETE", %r{/api/tasks/700$}],
    ].each do |args, method, path|
      @server.inject(method, path, {})
      doc, err, status = json(*args)
      assert_equal 1, status.exitstatus, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      @server.inject(method, path, 403)
      doc, err, status = json(*args)
      assert_equal 1, status.exitstatus, err
      assert_equal "authorization_error", doc.dig("error", "code")
      assert_equal false, doc.dig("meta", "changed")
    end
  end

  def test_cleanup_failure_cannot_mask_a_success_or_unknown_write
    @server.inject("DELETE", %r{/api/access-tokens/me$}, 403, times: 2)
    doc, err, status = json("update", "task", "700", "--completed", "true")
    assert status.success?, err
    assert_equal true, doc.dig("meta", "changed")
    assert_includes err, "session cleanup failed"
    @server.inject("DELETE", %r{/api/tasks/700$}, :apply_then_drop)
    doc, err, status = json("delete", "task", "700")
    assert_equal 1, status.exitstatus
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("data", "deleted")
    assert_includes err, "session cleanup failed"
  end

  def test_offline_root_group_and_leaf_help_cover_every_task_verb_and_alias
    %w[get create update move delete].each do |verb|
      [[verb, "--help"], [verb, "task", "--help"], [verb, "tasks", "--help"]].each do |args|
        out, err, status = planka(*args, env: { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil })
        assert status.success?, err
        assert_includes out, "task"
      end
    end
    assert_empty @server.requests
  end

  def test_individual_task_list_scope_excludes_other_lists_and_ambiguity_reports_ids
    @server.tasks.find { |t| t["id"] == "702" }["name"] = "Verify"
    doc, err, status = json("get", "task", "702", "--task-list", "600")
    assert_equal 1, status.exitstatus, err
    assert_equal "not_found", doc.dig("error", "code")
    doc, err, status = json("get", "task", "Verify", "--task-list", "600")
    assert_equal 2, status.exitstatus, err
    assert_equal "Ambiguous task name; candidate IDs: 700, 701", doc.dig("error", "message")
    doc, err, status = json("get", "task", "Verify", "--task-list", "601")
    assert status.success?, err
    assert_equal "702", doc.dig("data", "id")
  end
end
