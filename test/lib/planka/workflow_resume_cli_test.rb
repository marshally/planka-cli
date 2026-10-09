require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"

class Planka::WorkflowResumeCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, stdin: "", executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-resume-password", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args,
                   chdir: Dir.tmpdir, stdin_data: stdin)
  end

  def test_nested_help_is_offline_at_every_level
    env = { "PLANKA_AGENT_PASSWORD" => nil }
    out, err, status = planka("workflow", "resume", "--help", env: env)
    assert status.success?, err
    assert_includes out, "usage: planka workflow resume <resource> REF [flags]"
    assert_includes out, "ticket CARD --criteria-file FILE"
    out, err, status = planka("workflow", "resume", "ticket", "--help", env: env)
    assert status.success?, err
    assert_includes out, "usage: planka workflow resume ticket CARD --criteria-file FILE|- [--output human|json]"
    out, err, status = planka("workflow", "resume", "tickets", "-h", env: env)
    assert status.success?, err
    assert_includes out, "usage: planka workflow resume ticket CARD"
    [["workflow", "--help"], ["--help"]].each do |args|
      out, err, status = planka(*args, env: env)
      assert status.success?, err
      assert_includes out, "resume ticket CARD"
    end
    assert_empty @server.requests
  end

  def test_offline_guide_resumes_partial_tickets_with_the_canonical_command
    out, err, status = planka("workflow", "guide", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert status.success?, err
    assert_includes out, "planka workflow resume ticket CARD --criteria-file FILE"
    refute_includes out, "create-ticket --card"
  end

  def test_invalid_invocations_and_criteria_exit_2_before_any_request
    path = criteria_file(["Ok"])
    invocations = [
      [["workflow", "resume"], ""], [["workflow", "resume", "ticket"], ""], [["workflow", "resume", "dragon", CARD], ""],
      [["workflow", "resume", "ticket", CARD, "extra", "--criteria-file", path], ""],
      [["workflow", "resume", "ticket", CARD, "--board", "1", "--criteria-file", path], ""],
      [["workflow", "resume", "ticket", "not-a-card", "--criteria-file", path], ""],
      [["workflow", "resume", "ticket", "https://other.example/cards/#{CARD}", "--criteria-file", path], ""],
      [["workflow", "resume", "ticket", CARD], ""],
      [["workflow", "resume", "ticket", CARD, "--criteria-file", path, "--criteria-file", criteria_file(["Other"])], ""],
      [["workflow", "resume", "ticket", CARD, "--criteria-file", File.join(Dir.tmpdir, "missing-criteria.json")], ""],
      [["describe", "card", CARD, "--criteria-file", path], ""]
    ]
    ["not json", "{}", "[]", "[1]", "[\"\"]", "[\"  \"]", "[\"a\", \"a\"]", JSON.generate(["x" * 1025]),
     "[\"\xFF\"]".b, "[\"a\", null]"].each do |document|
      invocations << [["workflow", "resume", "ticket", CARD, "--criteria-file", "-"], document]
    end
    invocations.each do |args, stdin|
      out, err, status = planka("-o", "json", *args, stdin: stdin)
      assert_equal 2, status.exitstatus, "#{args.inspect} #{stdin.inspect}: #{out}#{err}"
      doc = JSON.parse(out)
      assert_equal "invalid_input", doc.dig("error", "code")
      assert_nil doc["data"]
    end
    assert_empty @server.requests
  end

  def test_missing_connection_settings_precede_criteria_checks_without_requests
    out, err, status = planka("workflow", "resume", "ticket", CARD, "-o", "json", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert_equal 1, status.exitstatus, err
    doc = JSON.parse(out)
    assert_equal "configuration_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_empty @server.requests
  end

  def test_resume_creates_the_missing_criteria_list_and_every_criterion_in_order
    criteria = ["First: \"quoted\"", "Second\nwith newline ✓"]
    out, err, status = planka("workflow", "resume", "ticket", "#{@server.base_url}/cards/#{CARD}",
                              "--criteria-file", criteria_file(criteria), "-o", "json")
    assert status.success?, err
    assert_empty err
    doc = JSON.parse(out)
    assert_nil doc["error"]
    assert_equal({ "changed" => true }, doc["meta"])
    list_id, first_id, second_id = "1900000000000000001", "1900000000000000002", "1900000000000000003"
    assert_equal({ "card" => { "id" => CARD, "name" => "Spec: Work-next refinement", "url" => "#{@server.base_url}/cards/#{CARD}" },
                   "taskList" => { "id" => list_id, "name" => "Acceptance criteria", "created" => true },
                   "tasks" => [{ "id" => first_id, "name" => criteria[0], "isCompleted" => false, "created" => true },
                               { "id" => second_id, "name" => criteria[1], "isCompleted" => false, "created" => true }] }, doc["data"])
    assert_equal([["POST", "/api/cards/#{CARD}/task-lists", { "name" => "Acceptance criteria", "position" => 65_536, "showOnFrontOfCard" => true }],
                  ["POST", "/api/task-lists/#{list_id}/tasks", { "name" => criteria[0], "position" => 65_536 }],
                  ["POST", "/api/task-lists/#{list_id}/tasks", { "name" => criteria[1], "position" => 131_072 }]], writes)
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    out, err, status = planka("workflow", "pending-criteria", CARD, "-o", "json")
    assert status.success?, err
    assert_equal criteria, JSON.parse(out).dig("data", "criteria")
  end

  def test_existing_criteria_keep_completion_and_order_and_a_satisfied_ticket_is_a_noop
    seed_criteria_list(["Second", true, 65_536], ["Extra", false, 131_072])
    path = criteria_file(["First", "Second"])
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert status.success?, err
    doc = JSON.parse(out)
    assert_equal({ "changed" => true }, doc["meta"])
    assert_equal({ "id" => "900", "name" => "Acceptance criteria", "created" => false }, doc.dig("data", "taskList"))
    assert_equal([{ "id" => "1900000000000000001", "name" => "First", "isCompleted" => false, "created" => true },
                  { "id" => "901", "name" => "Second", "isCompleted" => true, "created" => false }], doc.dig("data", "tasks"))
    assert_equal([["POST", "/api/task-lists/900/tasks", { "name" => "First", "position" => 196_608 }]], writes)
    assert_equal([["Second", true, 65_536], ["Extra", false, 131_072], ["First", false, 196_608]],
                 @server.tasks.map { |task| task.values_at("name", "isCompleted", "position") })

    @server.requests.clear
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path)
    assert status.success?, err
    assert_equal "resumed: Spec: Work-next refinement (#{@server.base_url}/cards/#{CARD})\n" \
                 "criteria list created: false\ncriteria added: 0\ncriteria kept: 2\n", out
    assert_empty writes
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert status.success?, err
    assert_equal({ "changed" => false }, JSON.parse(out)["meta"])
    assert_equal 0, @server.counts("POST", %r{/api/lists/.+/cards\z})
  end

  def test_rejected_criterion_after_a_created_list_is_a_partial_failure_that_resume_completes
    path = criteria_file(["One", "Two"])
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, 403, skip: 1)
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    list_id = "1900000000000000001"
    assert_equal "partial_failure", doc.dig("error", "code")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal({ "id" => list_id, "name" => "Acceptance criteria", "created" => true }, doc.dig("data", "taskList"))
    assert_equal(["One"], doc.dig("data", "tasks").map { |task| task["name"] })
    assert_equal({ "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => CARD }, { "type" => "task-list", "id" => list_id }] },
                 doc.dig("error", "recovery"))
    assert_includes err, "HTTP 403"
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    refute_includes out + err, "private upstream body"

    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert status.success?, err
    assert_equal([false, true], JSON.parse(out).dig("data", "tasks").map { |task| task["created"] })
    assert_equal(["One", "Two"], @server.tasks.map { |task| task["name"] })
    assert_equal 1, @server.task_lists.size
    assert_equal 0, @server.counts("POST", %r{/api/lists/.+/cards\z})
  end

  def test_unknown_criterion_outcome_is_not_retried_and_a_rerun_adds_only_what_is_missing
    path = criteria_file(["One", "Two", "Three"])
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, :apply_then_drop, skip: 1)
    out, _err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal({ "id" => nil, "name" => "Two", "isCompleted" => nil, "created" => nil }, doc.dig("data", "tasks").last)
    assert_equal 2, @server.counts("POST", %r{/api/task-lists/.+/tasks\z})

    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", path, "-o", "json")
    assert status.success?, err
    assert_equal([false, false, true], JSON.parse(out).dig("data", "tasks").map { |task| task["created"] })
    assert_equal(["One", "Two", "Three"], @server.tasks.map { |task| task["name"] })
  end

  def test_an_unknown_first_write_has_unknown_effect_and_invents_no_ids
    @server.inject("POST", %r{/api/cards/.+/task-lists\z}, :apply_then_drop)
    out, _err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_equal({ "id" => nil, "name" => "Acceptance criteria", "created" => nil }, doc.dig("data", "taskList"))
    assert_empty doc.dig("data", "tasks")
    assert_equal({ "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => CARD }] }, doc.dig("error", "recovery"))
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("data", "taskList", "created")
    assert_equal 1, @server.task_lists.size
  end

  def test_malformed_write_responses_report_uncertainty
    [[%r{/api/cards/.+/task-lists\z}, { "item" => nil }], [%r{/api/cards/.+/task-lists\z}, { "item" => { "id" => "77", "cardId" => "1", "name" => "Acceptance criteria" } }],
     [%r{/api/task-lists/.+/tasks\z}, { "item" => { "id" => "78", "taskListId" => "900", "name" => "Other", "isCompleted" => false } }]].each do |pattern, payload|
      @server.task_lists.clear
      seed_criteria_list if pattern.source.include?("tasks")
      @server.inject("POST", pattern, payload)
      out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
      assert_equal 1, status.exitstatus, out + err
      assert_equal "unknown_outcome", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out).dig("meta", "changed")
      refute_match(/KeyError|NoMethodError|TypeError/, out + err)
    end
  end

  def test_rejected_first_write_preserves_the_primary_category_without_effects
    @server.inject("POST", %r{/api/cards/.+/task-lists\z}, 403)
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "authorization_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_nil doc.dig("data", "taskList")
    refute_includes out + err, "private upstream body"
  end

  def test_duplicate_criteria_lists_fail_before_writes
    seed_criteria_list(["One", false, 1])
    seed_criteria_list(id: "950")
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["Two"]), "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "ambiguous_criteria_list", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_includes err, "candidate IDs: 900, 950"
    assert_empty writes
  end

  def test_read_failures_preserve_categories_without_writes
    [["POST", %r{access-tokens$}, 401, "authentication_error"], ["GET", %r{/cards/#{CARD}$}, 404, "not_found"],
     ["GET", %r{/cards/#{CARD}$}, :malformed_card, "api_error"], ["GET", %r{/cards/#{CARD}$}, :malformed_included, "api_error"],
     ["GET", %r{/cards/#{CARD}$}, :server_error, "api_error"]].each do |method, pattern, fault, code|
      @server.inject(method, pattern, fault)
      out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
      assert_equal 1, status.exitstatus, out + err
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_equal false, JSON.parse(out).dig("meta", "changed")
      refute_match(/KeyError|NoMethodError|TypeError|private upstream body|injected failure/, out + err)
    end
    seed_criteria_list(["One", false, 1])
    @server.tasks.first["name"] = 42
    out, _err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", criteria_file(["One"]), "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_empty writes
  end

  def test_success_survives_cleanup_failure_and_stdin_supplies_criteria
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "resume", "ticket", CARD, "--criteria-file", "-", "-o", "json", stdin: '["From stdin ✓"]')
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal(["From stdin ✓"], @server.tasks.map { |task| task["name"] })
    assert_includes err, "session cleanup failed; the operation result is unchanged"
  end

  def test_legacy_create_ticket_names_both_replacements_and_keeps_its_contract
    [["create-ticket", "--help"], ["--help"]].each do |args|
      out, err, status = planka(*args, executable: args.size == 2 ? "planka" : "planka-create-ticket")
      assert status.success?, err
      assert_includes out, "Canonical replacement for creation: planka workflow create ticket"
      assert_includes out, "Canonical replacement for --card: planka workflow resume ticket CARD --criteria-file FILE"
      assert_includes out, "workflow create ticket"
    end
    seed_criteria_list(["One", true, 65_536])
    out, err, status = planka("create-ticket", "--card", CARD, "--criteria-file", criteria_file(["One", "Two"]), "--output", "json")
    assert status.success?, err
    doc = JSON.parse(out)
    assert_equal %w[card completed taskList tasks], doc.keys.sort
    assert_equal([true, false], doc["tasks"].map { |task| task["reused"] })
    out, err, status = planka("--card", CARD, "--criteria-file", criteria_file(["Three"]), executable: "planka-create-ticket")
    assert status.success?, err
    assert_includes out, "Acceptance criteria: 1"
  end

  private

  def seed_criteria_list(*tasks, id: "900", name: "Acceptance criteria")
    @server.task_lists << { "id" => id, "cardId" => CARD, "name" => name, "position" => 65_536 }
    tasks.each_with_index do |(task_name, completed, position), index|
      @server.tasks << { "id" => "#{id.to_i + index + 1}", "taskListId" => id, "name" => task_name,
                         "isCompleted" => completed, "position" => position, "linkedCardId" => nil }
    end
  end

  # Resource writes, excluding session sign-in and sign-out.
  def writes
    @server.requests.reject { |method, path, _| method == "GET" || path.include?("access-tokens") }
           .map { |method, path, body| [method, path, JSON.parse(body.to_s.empty? ? "{}" : body)] }
  end

  def criteria_file(criteria)
    path = File.join(@dir ||= Dir.mktmpdir, "criteria-#{criteria.hash.abs}.json")
    File.write(path, JSON.generate(criteria))
    path
  end
end
