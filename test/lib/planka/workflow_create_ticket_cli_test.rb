require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class WorkflowCreateTicketCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, stdin: "")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-ticket-password", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args,
                   chdir: Dir.tmpdir, stdin_data: stdin)
  end

  def test_creates_project_ticket_with_ordered_incomplete_unicode_criteria
    criteria = File.join(Dir.tmpdir, "ticket-criteria-#{Process.pid}.json")
    File.write(criteria, JSON.generate(["Café\nsecond line", "再試行 ✓"]))
    @server.boards.first["defaultCardType"] = "story"
    out, err, status = planka("workflow", "create", "ticket", "--list", "ready-for-agent", "--board", FakePlanka::BOARD_ID,
                              "--name", "Search", "--criteria-file", criteria, "--description-file", "-", "-o", "json", stdin: "Multiline\n✓")

    assert status.success?, err
    result = JSON.parse(out)
    assert_equal({ "changed" => true }, result["meta"])
    assert_equal ["Search", "Multiline\n✓", "project"], result.dig("data", "card").values_at("name", "description", "type")
    assert_equal(["Café\nsecond line", "再試行 ✓"], result.dig("data", "tasks").map { |task| task["name"] })
    assert_equal([false, false], result.dig("data", "tasks").map { |task| task["isCompleted"] })
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
    assert_equal 1, @server.task_lists.size
    assert_equal(["Café\nsecond line", "再試行 ✓"], @server.tasks.map { |task| task["name"] })
    human, human_err, human_status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY,
                                            "--name", "Human ticket", "--criteria-file", criteria_file(["Done"]))
    assert human_status.success?, human_err
    created = @server.cards.last
    assert_equal "Created ticket: Human ticket (#{@server.base_url}/cards/#{created["id"]}, ID: #{created["id"]})\nAcceptance criteria: 1\n", human
  ensure
    File.delete(criteria) if criteria && File.exist?(criteria)
  end

  def test_criteria_read_failure_keeps_the_confirmed_card_and_resume_recovery
    criteria = criteria_file(["One"])
    @server.inject("GET", %r{/api/cards/1900000000000000001\z}, :server_error)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal "partial_failure", result.dig("error", "code")
    assert_equal true, result.dig("meta", "changed")
    assert_equal ["1900000000000000001", FakePlanka::BOARD_ID, FakePlanka::LIST_READY, "Search", "project"],
                 result.dig("data", "card").values_at("id", "boardId", "listId", "name", "type")
    assert_equal({ "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => "1900000000000000001" }] },
                 result.dig("error", "recovery"))
    assert_empty @server.task_lists

    _, err, status = planka("workflow", "resume", "ticket", "1900000000000000001", "--criteria-file", criteria, "-o", "json")
    assert status.success?, err
    assert_equal(["One"], @server.tasks.map { |task| task["name"] })
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
  end

  def test_created_card_and_list_are_retained_when_the_first_criteria_write_is_rejected
    criteria = criteria_file(["One"])
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, 403)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["partial_failure", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal "1900000000000000001", result.dig("data", "card", "id")
    assert_equal ["1900000000000000002", "Acceptance criteria", true],
                 result.dig("data", "taskList").values_at("id", "name", "created")
    assert_equal({ "action" => "resume-ticket", "resources" => [
                   { "type" => "card", "id" => "1900000000000000001" }, { "type" => "task-list", "id" => "1900000000000000002" }
                 ] }, result.dig("error", "recovery"))
  end

  def test_dual_stdin_is_rejected_before_reading_or_network_access
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", "-", "--description-file", "-", "-o", "json", stdin: "not consumed")

    assert_equal 2, status.exitstatus, err
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_empty @server.requests
  end

  def test_unknown_card_create_is_not_retried_and_preserves_readback_recovery
    @server.inject("POST", %r{/api/lists/.+/cards\z}, :apply_then_drop)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Uncertain",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", nil], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal %w[card taskList tasks], result.fetch("data").keys
    assert_nil result.dig("data", "card", "id")
    assert_equal "readback-cards", result.dig("error", "recovery", "action")
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
    refute(@server.requests.any? { |method, path, _| method == "POST" && path.match?(%r{/task-lists|/tasks}) })
  end

  def test_malformed_card_response_with_a_valid_id_uses_card_readback_without_criteria_writes
    id = "1900000000000000099"
    @server.inject("POST", %r{/api/lists/.+/cards\z}, { "item" => { "id" => id } })
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal %w[card taskList tasks], result.fetch("data").keys
    assert_equal ["unknown_outcome", nil, id], [result.dig("error", "code"), result.dig("meta", "changed"), result.dig("data", "card", "id")]
    assert_equal "readback-card", result.dig("error", "recovery", "action")
    assert_equal [{ "type" => "card", "id" => id }], result.dig("error", "recovery", "resources")
    refute(@server.requests.any? { |method, path, _| method == "POST" && path.match?(%r{/task-lists|/tasks}) })
  end

  def test_rejected_card_create_has_nested_empty_ticket_data_and_changed_false
    @server.inject("POST", %r{/api/lists/.+/cards\z}, 403)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal %w[card taskList tasks], result.fetch("data").keys
    assert_equal ["authorization_error", false], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_nil result.dig("data", "card", "id")
    assert_nil result.dig("data", "taskList")
    assert_empty result.dig("data", "tasks")
    assert_equal "readback-cards", result.dig("error", "recovery", "action")
    assert_empty @server.task_lists
  end

  def test_unknown_later_criterion_retains_confirmed_tasks_and_resumes_without_duplicate_card
    criteria = criteria_file(["One", "Two", "Three"])
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, :apply_then_drop, skip: 1)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    partial = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [partial.dig("error", "code"), partial.dig("meta", "changed")]
    assert_equal(["One", "Two"], partial.dig("data", "tasks").map { |task| task["name"] })
    assert_match(/\A\d+\z/, partial.dig("data", "tasks", 0, "id"))
    assert_equal [nil, nil], partial.dig("data", "tasks", 1).values_at("id", "created")

    out, err, status = planka("workflow", "resume", "ticket", partial.dig("data", "card", "id"), "--criteria-file", criteria, "-o", "json")
    assert status.success?, err
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
    assert_equal(["One", "Two", "Three"], @server.tasks.map { |task| task["name"] })
    assert_equal([false, false, true], JSON.parse(out).dig("data", "tasks").map { |task| task["created"] })
  end

  def test_numeric_list_ignores_bad_default_and_position_is_sent_to_the_card_create
    criteria = criteria_file(["One"])
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "--position", "0", "-o", "json",
                              env: { "PLANKA_BOARD_ID" => "invalid-default" })

    assert status.success?, err
    result = JSON.parse(out)
    card = result.dig("data", "card")
    assert_equal [FakePlanka::BOARD_ID, FakePlanka::LIST_READY, 0], card.values_at("boardId", "listId", "position")
    card_write = @server.requests.find { |method, path, _| method == "POST" && path.match?(%r{/cards\z}) }
    assert_equal({ "type" => "project", "name" => "Search", "position" => 0 }, JSON.parse(card_write.last))
  end

  def test_invalid_criteria_and_dual_input_files_fail_before_authentication
    invalid_docs = ["not json", "{}", "[]", '["a", "a"]', '[" "]', JSON.generate(["x" * 1025])]
    invalid_docs.each do |document|
      out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                                "--criteria-file", "-", "-o", "json", stdin: document)
      assert_equal 2, status.exitstatus, err
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    end
    assert_empty @server.requests
  end

  def test_missing_flags_and_unreadable_files_fail_before_requests
    missing = [[], ["--list", FakePlanka::LIST_READY], ["--name", "Search"],
               ["--list", FakePlanka::LIST_READY, "--name", "Search"]]
    missing.each do |args|
      out, err, status = planka("workflow", "create", "ticket", *args, "-o", "json")
      assert_equal 2, status.exitstatus, err
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    end
    [["--list", FakePlanka::LIST_READY, "--name", "Search", "--criteria-file", "/tmp/no-ticket-file"],
     ["--list", FakePlanka::LIST_READY, "--name", "Search", "--criteria-file", criteria_file(["One"]), "--description-file", "/tmp/no-description"]].each do |args|
      out, err, status = planka("workflow", "create", "ticket", *args, "-o", "json")
      assert_equal 2, status.exitstatus, err
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    end
    assert_empty @server.requests
  end

  def test_missing_configuration_precedes_file_reads_and_cleanup_preserves_outcomes
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", "/tmp/no-ticket-file", "-o", "json", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert_equal 1, status.exitstatus, err
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_empty @server.requests

    criteria = criteria_file(["One"])
    @server.inject("DELETE", %r{access-tokens/me\z}, 403)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "-o", "json")
    assert status.success?, err
    assert_equal true, JSON.parse(out).dig("meta", "changed")
    assert_includes err, "session cleanup failed; the operation result is unchanged"

    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, 403)
    @server.inject("DELETE", %r{access-tokens/me\z}, 403)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Partial",
                              "--criteria-file", criteria, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal ["partial_failure", true], [JSON.parse(out).dig("error", "code"), JSON.parse(out).dig("meta", "changed")]
    assert_includes err, "session cleanup failed; the operation result is unchanged"
  end

  def test_a_created_criterion_response_must_confirm_it_is_incomplete
    criteria = criteria_file(["One"])
    list_id = "1900000000000000002"
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, { "item" => { "id" => "1900000000000000003", "taskListId" => list_id,
                                                                         "name" => "One", "isCompleted" => true, "position" => 65_536 } })
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria, "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal "1900000000000000001", result.dig("data", "card", "id")
    assert_equal list_id, result.dig("data", "taskList", "id")
    assert_equal({ "id" => "1900000000000000003", "name" => "One", "isCompleted" => nil, "created" => nil }, result.dig("data", "tasks").last)
  end

  def test_malformed_created_task_position_is_unknown_and_stops_later_criterion_writes
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, { "item" => { "id" => "1900000000000000003",
                                                                         "taskListId" => "1900000000000000002",
                                                                         "name" => "One", "isCompleted" => false } })
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One", "Two"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal 1, @server.counts("POST", %r{/api/task-lists/.+/tasks\z})
    assert_equal [{ "id" => "1900000000000000003", "name" => "One", "isCompleted" => nil, "created" => nil }], result.dig("data", "tasks")
  end

  def test_later_criterion_cannot_reuse_a_confirmed_created_task_id
    repeated_id = "1900000000000000003"
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, { "item" => { "id" => repeated_id,
                                                                         "taskListId" => "1900000000000000002",
                                                                         "name" => "Two", "isCompleted" => false,
                                                                         "position" => 131_072 } }, skip: 1)
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One", "Two", "Three"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal [{ "id" => repeated_id, "name" => "One", "isCompleted" => false, "created" => true },
                  { "id" => nil, "name" => "Two", "isCompleted" => nil, "created" => nil }], result.dig("data", "tasks")
    assert_equal 2, @server.counts("POST", %r{/api/task-lists/.+/tasks\z})
  end

  def test_malformed_created_task_list_retains_only_a_fresh_id_from_the_target_card
    card_id = "1900000000000000001"
    list_id = "1900000000000000002"
    @server.inject("POST", %r{/api/cards/.+/task-lists\z}, { "item" => { "id" => list_id, "cardId" => card_id,
                                                                         "name" => "Wrong name", "position" => 131_072 } })
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal({ "id" => list_id, "name" => "Acceptance criteria", "created" => nil }, result.dig("data", "taskList"))
    assert_equal [{ "type" => "card", "id" => card_id }, { "type" => "task-list", "id" => list_id }], result.dig("error", "recovery", "resources")
    assert_empty result.dig("data", "tasks")
  end

  def test_untrusted_task_list_id_is_not_exposed_for_invalid_or_other_card_identities
    card_id = "1900000000000000001"
    [
      { "id" => "unsafe", "cardId" => card_id, "name" => "Wrong name", "position" => 131_072 },
      { "id" => "1900000000000000002", "cardId" => "999", "name" => "Wrong name", "position" => 131_072 },
    ].each do |record|
      @server.inject("POST", %r{/api/cards/.+/task-lists\z}, { "item" => record })
      out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                                "--criteria-file", criteria_file(["One"]), "-o", "json")
      assert_equal 1, status.exitstatus, out + err
      result = JSON.parse(out)
      assert_equal "unknown_outcome", result.dig("error", "code")
      assert_nil result.dig("data", "taskList", "id")
      assert_equal [{ "type" => "card", "id" => result.dig("data", "card", "id") }], result.dig("error", "recovery", "resources")
    end
  end

  def test_task_list_id_observed_in_the_created_card_scope_is_not_reused_as_new
    card_id = "1900000000000000001"
    reused_list_id = "1900000000000000002"
    inject_created_card_scope(card_id, [{ "id" => reused_list_id, "cardId" => card_id, "name" => "Other", "position" => 65_536 }], [])
    @server.inject("POST", %r{/api/cards/.+/task-lists\z}, { "item" => { "id" => reused_list_id, "cardId" => card_id,
                                                                         "name" => "Wrong name", "position" => 131_072 } })
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal "unknown_outcome", result.dig("error", "code")
    assert_nil result.dig("data", "taskList", "id")
    assert_equal [{ "type" => "card", "id" => card_id }], result.dig("error", "recovery", "resources")
  end

  def test_task_id_observed_in_another_task_list_is_not_reused_as_new
    card_id = "1900000000000000001"
    list_id = "1900000000000000002"
    reused_task_id = "1900000000000000003"
    inject_created_card_scope(card_id, [{ "id" => "900", "cardId" => card_id, "name" => "Other", "position" => 65_536 }],
                              [{ "id" => reused_task_id, "taskListId" => "900", "name" => "Occupied", "isCompleted" => false,
                                 "position" => 65_536 }])
    out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                              "--criteria-file", criteria_file(["One"]), "-o", "json")

    assert_equal 1, status.exitstatus, out + err
    result = JSON.parse(out)
    assert_equal ["unknown_outcome", true], [result.dig("error", "code"), result.dig("meta", "changed")]
    assert_equal list_id, result.dig("data", "taskList", "id")
    assert_equal ["unknown_outcome", nil], [result.dig("error", "code"), result.dig("data", "tasks", 0, "id")]
    assert_equal 1, @server.counts("POST", %r{/api/task-lists/.+/tasks\z})
  end

  def test_invalid_or_other_task_parent_identity_is_not_exposed
    [
      { "id" => "unsafe", "taskListId" => "1900000000000000002", "name" => "One", "isCompleted" => false,
        "position" => 65_536 },
      { "id" => "1900000000000000003", "taskListId" => "999", "name" => "One", "isCompleted" => false,
        "position" => 65_536 },
    ].each do |record|
      @server.stop
      @server = FakePlanka.new
      @server.inject("POST", %r{/api/cards/.+/task-lists\z}, { "item" => { "id" => "1900000000000000002",
                                                                           "cardId" => "1900000000000000001",
                                                                           "name" => "Acceptance criteria",
                                                                           "position" => 131_072 } })
      @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, { "item" => record })
      out, err, status = planka("workflow", "create", "ticket", "--list", FakePlanka::LIST_READY, "--name", "Search",
                                "--criteria-file", criteria_file(["One"]), "-o", "json")
      assert_equal 1, status.exitstatus, out + err
      result = JSON.parse(out)
      assert_equal "unknown_outcome", result.dig("error", "code")
      assert_nil result.dig("data", "tasks", 0, "id")
      assert_equal [{ "type" => "card", "id" => result.dig("data", "card", "id") },
                    { "type" => "task-list", "id" => "1900000000000000002" }], result.dig("error", "recovery", "resources")
    end
  end

  def test_leaf_alias_and_builtin_guide_are_offline_and_name_the_implemented_command
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    ["ticket", "tickets"].each do |name|
      out, err, status = planka("workflow", "create", name, "--help", env: offline)
      assert status.success?, err
      assert_includes out, "usage: planka workflow create ticket"
    end
    out, err, status = planka("workflow", "create", "--help", env: offline)
    assert status.success?, err
    assert_includes out, "ticket --list LIST --name NAME --criteria-file FILE"
    out, err, status = planka("workflow", "guide", env: offline)
    assert status.success?, err
    assert_includes out, "workflow create ticket"
    assert_empty @server.requests
  end

  private

  def criteria_file(criteria)
    path = File.join(Dir.tmpdir, "ticket-criteria-#{Process.pid}-#{criteria.hash.abs}.json")
    File.write(path, JSON.generate(criteria))
    path
  end

  def inject_created_card_scope(card_id, task_lists, tasks)
    @server.inject("GET", %r{/api/cards/#{card_id}\z}, {
                     "item" => { "id" => card_id, "name" => "Search" },
                     "included" => { "taskLists" => task_lists, "tasks" => tasks },
                   })
  end
end
