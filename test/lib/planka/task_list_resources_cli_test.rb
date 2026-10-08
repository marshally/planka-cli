require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class TaskListResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  BOARD = FakePlanka::BOARD_ID
  CARD = FakePlanka::PARENT_CARD
  CRITERIA = "600000000000000001".freeze
  NOTES = "600000000000000002".freeze
  OTHER_BOARD = "100000000000000009".freeze

  def setup
    @server = FakePlanka.new
    @server.task_lists << task_list(NOTES, "Notes", 131_072) << task_list(CRITERIA, "Acceptance criteria", 65_536)
    @server.tasks << { "id" => "700000000000000001", "taskListId" => CRITERIA, "name" => "Works", "isCompleted" => true, "position" => 65_536 }
  end

  def teardown = @server.stop

  def task_list(id, name, position, card: CARD)
    { "id" => id, "cardId" => card, "name" => name, "position" => position, "showOnFrontOfCard" => true,
      "hideCompletedTasks" => false, "createdAt" => "2026-09-01T00:00:00.000Z", "updatedAt" => nil }
  end

  def planka(*args, env: {}, executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-password", "PLANKA_BOARD_ID" => nil }
    out, err, status = Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args, chdir: Dir.tmpdir)
    [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status]
  end

  def writes
    @server.requests.reject { |method, path, _| method == "GET" || path.include?("access-tokens") }
           .map { |method, path, body| [method, path, body.empty? ? nil : JSON.parse(body)] }
  end

  def expected(overrides = {}) = task_list(CRITERIA, "Acceptance criteria", 65_536).merge(overrides)

  def test_get_task_list_reads_one_task_list_by_id_or_card_scoped_name_without_writes
    [[CRITERIA], [CRITERIA, "--card", CARD], ["Acceptance criteria", "--card", CARD],
     ["Acceptance criteria", "--card", "Spec: Work-next refinement", "--board", BOARD]].each do |reference|
      doc, err, status = json("get", "task-list", *reference)
      assert status.success?, "#{reference.inspect}: #{err}"
      assert_equal({ "data" => expected, "meta" => {}, "error" => nil }, doc, reference.inspect)
    end
    out, err, status = planka("get", "task-lists", CRITERIA)
    assert status.success?, err
    assert_equal "Acceptance criteria (#{CRITERIA}) on card #{CARD}", out.chomp
    assert_empty writes
  end

  def ids(doc) = doc["data"].map { |task_list| task_list["id"] }

  def test_card_collection_reads_task_lists_in_card_order_with_name_filters_before_limits
    doc, err, status = json("get", "task-lists", "--card", CARD)
    assert status.success?, err
    assert_equal [CRITERIA, NOTES], ids(doc), "ordered by position, not insertion"
    assert_equal({ "complete" => true }, doc["meta"])
    duplicate = "600000000000000003"
    @server.task_lists << task_list(duplicate, "Notes", 196_608)
    doc, err, status = json("get", "task-list", "--card", "Spec: Work-next refinement", "--board", BOARD, "--name", "Notes", "--limit", "1")
    assert status.success?, err
    assert_equal [[NOTES], false], [ids(doc), doc.dig("meta", "complete")]
    doc, err, status = json("get", "task-lists", "--card", CARD, "--name", "Notes", "--limit", "2")
    assert status.success?, err
    assert_equal [[NOTES, duplicate], true], [ids(doc), doc.dig("meta", "complete")]
    out, err, status = planka("get", "task-lists", "--card", CARD, "--limit", "1")
    assert status.success?, err
    assert_equal "Acceptance criteria (#{CRITERIA}) on card #{CARD}\nResults truncated; use a larger --limit or omit it.\n", out
    doc, err, status = json("get", "task-lists", "--card", CARD, "--name", "notes")
    assert status.success?, err
    assert_equal({ "data" => [], "meta" => { "complete" => true }, "error" => nil }, doc)
    out, err, status = planka("get", "task-lists", "--card", CARD, "--name", "missing")
    assert status.success?, err
    assert_equal "No task lists.", out.chomp
    assert_empty writes
  end

  def test_scope_references_and_filters_are_validated_before_requests
    [["get", "task-lists"], ["get", "task-lists", "--board", BOARD],
     ["get", "task-lists", "--card", CARD, "--label", "enhancement"], ["get", "task-lists", "--card", CARD, "--member", "ada"],
     ["get", "task-lists", "--card", CARD, "--limit", "0"], ["get", "task-lists", "--card", CARD, "--name", "a", "--name", "b"],
     ["get", "task-lists", "--card", CARD, "--card", "400000000000000002"], ["get", "task-list", CRITERIA, "--limit", "1"],
     ["get", "task-list", "Acceptance criteria"], ["get", "task-list", "Acceptance criteria", "--board", BOARD],
     ["get", "task-list", "#{@server.base_url}/task-lists/#{CRITERIA}", "--card", CARD],
     ["get", "task-list", "#{@server.base_url}//#{CRITERIA}"], ["get", "task-list", "/#{CRITERIA}"]].each do |args|
      doc, err, status = json(*args, env: { "PLANKA_BOARD_ID" => BOARD })
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
    end
    doc, = json("get", "task-list", "#{@server.base_url}/task-lists/#{CRITERIA}")
    assert_equal "Expected a numeric task list ID or exact task list name", doc.dig("error", "message"), "no task-list URL form is promised"
    assert_equal 0, @server.requests.size
  end

  def test_explicit_parent_mismatches_and_missing_task_lists_fail
    other = @server.add_card("Other", FakePlanka::LIST_READY)
    doc, _err, status = json("get", "task-list", CRITERIA, "--card", other)
    assert_equal [2, "invalid_input", "Task list does not belong to --card"], [status.exitstatus, doc.dig("error", "code"), doc.dig("error", "message")]
    @server.add_board(OTHER_BOARD)
    doc, _err, status = json("get", "task-list", CRITERIA, "--board", OTHER_BOARD)
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
    assert_match(/does not belong to --board/, doc.dig("error", "message"))
    doc, _err, status = json("get", "task-list", "Acceptance criteria", "--card", other)
    assert_equal [1, "not_found"], [status.exitstatus, doc.dig("error", "code")]
    doc, _err, status = json("get", "task-list", "600000000000000099")
    assert_equal [1, "not_found"], [status.exitstatus, doc.dig("error", "code")]
    @server.task_lists << task_list(NOTES, "Notes", 1)
    doc, _err, status = json("get", "task-list", "Notes", "--card", CARD)
    assert_equal [1, "api_error"], [status.exitstatus, doc.dig("error", "code")], "duplicate task-list IDs are malformed"
    assert_empty writes
  end

  def created(id, name, position) = task_list(id, name, position).merge("createdAt" => "2026-10-01T00:00:00.000Z")

  def test_create_appends_after_the_cards_task_lists_with_native_defaults_even_for_existing_names
    doc, err, status = json("create", "task-list", "--card", CARD, "--name", "Ünïcode notes")
    assert status.success?, err
    record = @server.task_lists.last
    assert_equal({ "data" => created(record["id"], "Ünïcode notes", 196_608), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["POST", "/api/cards/#{CARD}/task-lists", { "name" => "Ünïcode notes", "position" => 196_608 }]], writes,
                 "only name and position; Planka's own display defaults apply"
    @server.requests.clear
    out, err, status = planka("create", "task-lists", "--card", "Spec: Work-next refinement", "--board", BOARD, "--name", "Notes", "--position", "1")
    assert status.success?, err
    assert_match(/\ACreated task list Notes \(\d+\) on card #{CARD}\n\z/, out)
    assert_equal [["POST", "/api/cards/#{CARD}/task-lists", { "name" => "Notes", "position" => 1 }]], writes, "an existing name is still created"
    assert_equal(2, @server.task_lists.count { |task_list| task_list["name"] == "Notes" })
  end

  def test_create_inputs_are_validated_before_any_request
    [["create", "task-list", "--name", "x"], ["create", "task-list", "--card", CARD],
     ["create", "task-list", "--card", CARD, "--name", ""], ["create", "task-list", "--card", CARD, "--name", "x" * 129],
     ["create", "task-list", "--card", CARD, "--name", "x", "--position", "-1"],
     ["create", "task-list", "--card", CARD, "--name", "x", "--position", "Infinity"],
     ["create", "task-list", "--card", CARD, "--name", "x", "--show-on-front-of-card"],
     ["create", "task-list", "--card", "Spec: Work-next refinement", "--name", "x"],
     ["create", "task-list", CRITERIA, "--card", CARD, "--name", "x"]].each do |args|
      doc, err, status = json(*args)
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
      refute_match(/unknown command/, err, args.inspect)
    end
    assert_equal 0, @server.requests.size
    doc, err, status = json("create", "task-list", "--card", CARD, "--name", "x" * 128)
    assert status.success?, err
    assert_equal 128, doc.dig("data", "name").size
  end

  def test_create_failures_report_no_invented_id_and_are_not_retried
    @server.inject("POST", %r{/task-lists\z}, :apply_then_drop)
    doc, _err, status = json("create", "task-list", "--card", CARD, "--name", "Review")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal [nil, CARD], doc["data"].values_at("id", "cardId")
    assert_equal({ "action" => "readback-task-lists", "resources" => [{ "type" => "card", "id" => CARD }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/task-lists\z})
    @server.inject("POST", %r{/task-lists\z}, { "item" => { "id" => "1" } })
    doc, _err, status = json("create", "task-list", "--card", CARD, "--name", "Malformed")
    assert_equal [1, "unknown_outcome"], [status.exitstatus, doc.dig("error", "code")]
    @server.inject("POST", %r{/task-lists\z}, 403)
    doc, _err, status = json("create", "task-list", "--card", CARD, "--name", "Forbidden")
    assert_equal [1, "authorization_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
  end

  def test_malformed_task_lists_report_an_incomplete_failed_read
    @server.task_lists << task_list("600000000000000009", 42, 1)
    doc, err, status = json("get", "task-lists", "--card", CARD)
    assert_equal 1, status.exitstatus, err
    assert_equal({ "data" => [], "meta" => { "complete" => false } }, doc.slice("data", "meta"))
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end
end
