require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class ListResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  BOARD = FakePlanka::BOARD_ID
  READY = FakePlanka::LIST_READY
  PROGRESS = FakePlanka::LIST_PROGRESS
  DONE = FakePlanka::LIST_DONE
  OTHER_BOARD = "100000000000000009".freeze

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

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

  def expected_list(overrides = {})
    { "id" => READY, "name" => "ready-for-agent", "type" => "active", "color" => nil, "boardId" => BOARD,
      "position" => 65_536, "createdAt" => nil, "updatedAt" => nil }.merge(overrides)
  end

  def test_get_list_reads_one_list_by_id_url_or_board_scoped_name_without_writes
    elsewhere = { "PLANKA_BOARD_ID" => OTHER_BOARD }
    [[[READY], elsewhere], [["#{@server.base_url}/lists/#{READY}"], elsewhere], [["ready-for-agent", "--board", BOARD], elsewhere],
     [["ready-for-agent"], { "PLANKA_BOARD_ID" => BOARD }]].each do |reference, env|
      doc, err, status = json("get", "list", *reference, env: env)
      assert status.success?, "#{reference.inspect}: #{err}"
      assert_equal({ "data" => expected_list, "meta" => {}, "error" => nil }, doc)
    end
    out, err, status = planka("get", "lists", READY)
    assert status.success?, err
    assert_equal "ready-for-agent (#{READY}) active on board #{BOARD}", out.chomp
    assert_empty writes
  end

  def ids(doc) = doc["data"].map { |list| list["id"] }

  def test_board_collection_reads_every_native_list_type_in_board_order
    archive = @server.add_list(nil, "archive")
    trash = @server.add_list("Trash", "trash")
    first = @server.add_list("triage", position: 1)
    doc, err, status = json("get", "lists", "--board", BOARD)
    assert status.success?, err
    assert_equal [first, READY, PROGRESS, DONE, archive, trash], ids(doc)
    assert_equal [nil, "archive"], doc["data"][4].values_at("name", "type")
    assert_equal({ "complete" => true }, doc["meta"])
    assert_nil doc["error"]
    out, err, status = planka("get", "list", "--board", BOARD, env: { "PLANKA_BOARD_ID" => OTHER_BOARD })
    assert status.success?, err
    assert_includes out.lines.map(&:chomp), "(unnamed) (#{archive}) archive on board #{BOARD}"
    assert_equal 6, out.lines.size
    assert_empty writes
  end

  def test_exact_name_filter_precedes_limits
    duplicate = @server.add_list("in-progress", "closed")
    doc, err, status = json("get", "lists", "--board", BOARD, "--name", "in-progress", "--limit", "1")
    assert status.success?, err
    assert_equal [PROGRESS], ids(doc)
    assert_equal false, doc.dig("meta", "complete")
    doc, err, status = json("get", "lists", "--board", BOARD, "--name", "in-progress", "--limit", "2")
    assert status.success?, err
    assert_equal [PROGRESS, duplicate], ids(doc)
    assert_equal true, doc.dig("meta", "complete")
    out, err, status = planka("get", "lists", "--board", BOARD, "--limit", "1")
    assert status.success?, err
    assert_includes out, "Results truncated"
    doc, err, status = json("get", "lists", "--board", BOARD, "--name", "In-Progress")
    assert status.success?, err
    assert_equal({ "data" => [], "meta" => { "complete" => true }, "error" => nil }, doc)
    out, err, status = planka("get", "lists", "--board", BOARD, "--name", "missing")
    assert status.success?, err
    assert_equal "No lists.", out.chomp
  end

  def test_collection_scope_and_filters_are_validated_before_requests
    [["get", "lists"], ["get", "lists", "--board", BOARD, "--label", "enhancement"],
     ["get", "lists", "--board", BOARD, "--member", "ada"], ["get", "lists", "--board", BOARD, "--limit", "0"],
     ["get", "lists", "--board", BOARD, "--name", "a", "--name", "b"], ["get", "list", READY, "--limit", "1"],
     ["get", "lists", "--board", "not a board"]].each do |args|
      doc, err, status = json(*args, env: { "PLANKA_BOARD_ID" => BOARD })
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
    end
    [["get", "lists"], ["get", "lists", "--board", "not a board"]].each do |args|
      doc, _err, _status = json(*args, env: { "PLANKA_BOARD_ID" => BOARD })
      assert_equal({ "complete" => false }, doc["meta"], args.inspect)
    end
    assert_equal 0, @server.requests.size
    @server.add_board(OTHER_BOARD)
    elsewhere = @server.add_list("elsewhere", board_id: OTHER_BOARD)
    doc, _err, status = json("get", "list", elsewhere, "--board", BOARD)
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], "explicit parent mismatches fail"
    assert_match(/does not belong to --board/, doc.dig("error", "message"))
  end

  def test_malformed_lists_report_an_incomplete_failed_read
    @server.lists << { "id" => "200000000000000099", "name" => 42, "type" => "active", "boardId" => BOARD, "position" => 1 }
    doc, err, status = json("get", "lists", "--board", BOARD)
    assert_equal 1, status.exitstatus, err
    assert_equal({ "data" => [], "meta" => { "complete" => false } }, doc.slice("data", "meta"))
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_create_appends_an_active_list_after_kanban_lists_ignoring_archive_and_trash
    @server.add_list(nil, "archive", position: 999_999)
    @server.add_list("Later", "closed", position: 131_072)
    doc, err, status = json("create", "list", "--board", BOARD, "--name", "Ünïcode review")
    assert status.success?, err
    assert_equal({ "changed" => true }, doc["meta"])
    created = @server.lists.last
    assert_equal expected_list("id" => created["id"], "name" => "Ünïcode review", "position" => 196_608), doc["data"]
    assert_equal [["POST", "/api/boards/#{BOARD}/lists", { "type" => "active", "name" => "Ünïcode review", "position" => 196_608 }]], writes
    @server.requests.clear
    out, err, status = planka("create", "lists", "--board", "#{@server.base_url}/boards/#{BOARD}", "--name", "Done", "--type", "closed", "--position", "1")
    assert status.success?, err
    assert_match(/\ACreated list Done \(\d+\) closed on board #{BOARD}\n\z/, out)
    assert_equal [["POST", "/api/boards/#{BOARD}/lists", { "type" => "closed", "name" => "Done", "position" => 1 }]], writes
  end

  def test_create_and_scope_inputs_are_validated_before_any_request
    [["create", "list", "--name", "x"],
     ["create", "list", "--board", BOARD],
     ["create", "list", "--board", BOARD, "--name", ""],
     ["create", "list", "--board", BOARD, "--name", "x" * 129],
     ["create", "list", "--board", BOARD, "--name", "x", "--type", "archive"],
     ["create", "list", "--board", BOARD, "--name", "x", "--type", "trash"],
     ["create", "list", "--board", BOARD, "--name", "x", "--position", "-1"],
     ["create", "list", "--board", BOARD, "--name", "x", "--position", "Infinity"],
     ["create", "list", "--board", BOARD, "--name", "x", "--color", "berry-red"],
     ["create", "list", READY, "--board", BOARD, "--name", "x"]].each do |args|
      doc, err, status = json(*args, env: { "PLANKA_BOARD_ID" => BOARD })
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
      refute_match(/unknown command/, err, args.inspect)
    end
    doc, err, status = json("create", "list", "--board", BOARD, "--name", "x" * 128)
    assert status.success?, err
    assert_equal 128, doc.dig("data", "name").size
    assert_equal 1, writes.size
  end

  def test_unknown_create_outcome_reports_no_invented_id_and_is_not_retried
    @server.inject("POST", %r{/api/boards/.+/lists\z}, :apply_then_drop)
    doc, _err, status = json("create", "list", "--board", BOARD, "--name", "Review")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_nil doc.dig("data", "id")
    assert_equal BOARD, doc.dig("data", "boardId")
    assert_equal({ "action" => "readback-lists", "resources" => [{ "type" => "board", "id" => BOARD }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/api/boards/.+/lists\z})
    @server.inject("POST", %r{/api/boards/.+/lists\z}, { "item" => { "id" => "1" } })
    doc, _err, status = json("create", "list", "--board", BOARD, "--name", "Malformed")
    assert_equal [1, "unknown_outcome"], [status.exitstatus, doc.dig("error", "code")]
    @server.inject("POST", %r{/api/boards/.+/lists\z}, 403)
    doc, _err, status = json("create", "list", "--board", BOARD, "--name", "Forbidden")
    assert_equal [1, "authorization_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
  end

  def test_update_sends_only_supplied_changed_fields_and_identical_updates_are_noops
    doc, err, status = json("update", "list", READY, "--name", "Ready")
    assert status.success?, err
    assert_equal({ "data" => expected_list("name" => "Ready"), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["PATCH", "/api/lists/#{READY}", { "name" => "Ready" }]], writes
    @server.requests.clear
    out, err, status = planka("update", "lists", "Ready", "--board", BOARD, "--name", "Ready", "--color", "lagoon-blue", "--position", "5")
    assert status.success?, err
    assert_equal "Updated list Ready (#{READY}) active on board #{BOARD}", out.chomp
    assert_equal [["PATCH", "/api/lists/#{READY}", { "color" => "lagoon-blue", "position" => 5 }]], writes, "unchanged name is not sent"
    @server.requests.clear
    doc, err, status = json("update", "list", READY, "--clear-color")
    assert status.success?, err
    assert_equal expected_list("name" => "Ready", "position" => 5), doc["data"]
    assert_equal [["PATCH", "/api/lists/#{READY}", { "color" => nil }]], writes, "clearing sends an explicit null"
    @server.requests.clear
    doc, err, status = json("update", "list", READY, "--clear-color", "--type", "active", "--position", "5")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_empty writes
    assert_equal [BOARD, "active"], @server.lists.find { |list| list["id"] == READY }.values_at("boardId", "type")
  end

  def test_type_changes_issue_one_write_and_keep_native_linked_task_effects
    card = @server.add_card("Blocker", PROGRESS)
    blocked = @server.add_card("Blocked", READY)
    @server.task_lists << { "id" => "910", "cardId" => blocked, "name" => "Blockers" }
    @server.tasks << { "id" => "911", "taskListId" => "910", "name" => "Blocker", "linkedCardId" => card, "isCompleted" => false }
    doc, err, status = json("update", "list", PROGRESS, "--type", "closed")
    assert status.success?, err
    assert_equal "closed", doc.dig("data", "type")
    assert_equal [["PATCH", "/api/lists/#{PROGRESS}", { "type" => "closed" }]], writes, "no client-side card or task writes"
    assert_equal true, @server.tasks.last["isCompleted"], "Planka completes tasks linked to the list's cards"
    @server.requests.clear
    doc, err, status = json("update", "list", PROGRESS, "--type", "active")
    assert status.success?, err
    assert_equal "active", doc.dig("data", "type")
    assert_equal [["PATCH", "/api/lists/#{PROGRESS}", { "type" => "active" }]], writes
    assert_equal false, @server.tasks.last["isCompleted"]
  end

  def test_update_inputs_are_validated_before_any_request
    [["update", "list", READY],
     ["update", "list", READY, "--board", BOARD],
     ["update", "list", "--name", "x"],
     ["update", "list", READY, "--color", "berry-red", "--clear-color"],
     ["update", "list", READY, "--color", "red"],
     ["update", "list", READY, "--name", ""],
     ["update", "list", READY, "--name", "x" * 129],
     ["update", "list", READY, "--type", "archive"],
     ["update", "list", READY, "--position", "-1"],
     ["update", "list", READY, "--position", "NaN"],
     ["update", "list", "ready-for-agent", "--name", "x"]].each do |args|
      doc, err, status = json(*args)
      assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
      refute_match(/unknown command/, err, args.inspect)
    end
    assert_equal 0, @server.requests.size
  end

  def test_archive_and_trash_lists_are_not_updated
    archive = @server.add_list(nil, "archive")
    trash = @server.add_list("Trash", "trash")
    doc, err, status = json("get", "list", archive, "--board", BOARD)
    assert status.success?, err
    assert_equal [nil, "archive"], doc["data"].values_at("name", "type"), "system lists are read through the board"
    [archive, "Trash"].each do |list|
      doc, _err, status = json("update", "list", list, "--board", BOARD, "--name", "Kept")
      assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], list
      assert_match(/archive and trash/i, doc.dig("error", "message"))
    end
    doc, _err, status = json("update", "list", trash, "--name", "Kept")
    assert_equal [1, "not_found"], [status.exitstatus, doc.dig("error", "code")]
    assert_match(/archive and trash lists need --board/, doc.dig("error", "message"))
    assert_empty writes
  end

  def test_update_failures_distinguish_rejected_from_unknown_outcomes
    @server.inject("PATCH", %r{/api/lists/}, 403)
    doc, _err, status = json("update", "list", READY, "--name", "Renamed")
    assert_equal [1, "authorization_error", false, expected_list], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
    @server.inject("PATCH", %r{/api/lists/}, { "item" => { "id" => READY } })
    doc, _err, status = json("update", "list", READY, "--name", "Renamed", "--clear-color")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal expected_list("name" => nil), doc["data"], "only the changed name is unknown"
    assert_equal({ "action" => "readback-list", "resources" => [{ "type" => "list", "id" => READY }] }, doc.dig("error", "recovery"))
    @server.inject("PATCH", %r{/api/lists/}, :apply_then_drop)
    doc, _err, status = json("update", "list", READY, "--position", "9")
    assert_equal [1, "unknown_outcome"], [status.exitstatus, doc.dig("error", "code")]
    assert_equal 3, @server.counts("PATCH", %r{/api/lists/}), "unknown updates are not retried"
  end

  def test_delete_issues_one_target_deletion_and_planka_moves_cards_to_trash
    card = @server.add_card("Doing", PROGRESS)
    doc, err, status = json("delete", "list", "in-progress", "--board", BOARD)
    assert status.success?, err
    assert_equal({ "data" => expected_list("id" => PROGRESS, "name" => "in-progress", "deleted" => true), "meta" => { "changed" => true },
                   "error" => nil }, doc)
    assert_equal [["DELETE", "/api/lists/#{PROGRESS}", nil]], writes, "no card is deleted or moved by the client"
    trash = @server.lists.find { |list| list["type"] == "trash" }
    assert_equal [trash["id"], nil], @server.find_card(card).values_at("listId", "position"), "Planka keeps the card in trash"
    out, err, status = planka("delete", "lists", DONE)
    assert status.success?, err
    assert_equal "Deleted list done (#{DONE}) from board #{BOARD}", out.chomp
  end

  def test_delete_requires_an_eligible_target_and_reports_rejected_or_unknown_outcomes
    doc, _err, status = json("delete", "list")
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
    assert_equal 0, @server.requests.size
    archive = @server.add_list(nil, "archive")
    doc, _err, status = json("delete", "list", archive, "--board", BOARD)
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
    assert_match(/archive and trash/i, doc.dig("error", "message"))
    assert_empty writes
    @server.inject("DELETE", %r{/api/lists/}, 403)
    doc, _err, status = json("delete", "list", READY)
    assert_equal [1, "authorization_error", false, expected_list], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
    @server.inject("DELETE", %r{/api/lists/}, :apply_then_drop)
    doc, _err, status = json("delete", "list", READY)
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal expected_list("deleted" => nil), doc["data"]
    assert_equal({ "action" => "readback-list", "resources" => [{ "type" => "list", "id" => READY }] }, doc.dig("error", "recovery"))
    assert_equal 2, @server.counts("DELETE", %r{/api/lists/}), "the unknown delete is not retried"
  end

  def test_help_is_offline_at_root_group_and_leaf_levels
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    { [] => "get lists --board BOARD", %w[--help] => "delete list LIST",
      %w[get --help] => "lists --board BOARD", %w[create --help] => "list --board BOARD --name NAME",
      %w[update --help] => "list LIST  Change only supplied list fields", %w[delete --help] => "list LIST  Delete one list",
      %w[get lists --help] => "usage: planka get lists --board BOARD", %w[get list -h] => "planka get list LIST",
      %w[create lists --help] => "usage: planka create list", %w[update list --help] => "--clear-color sends an explicit null",
      %w[update lists -h] => "usage: planka update list LIST", %w[delete list --help] => "moves the list's cards to the board's trash" }.each do |args, text|
      out, err, status = planka(*args, env: offline)
      assert status.success?, "#{args.inspect}: #{err}"
      assert_includes out, text, args.inspect
    end
    assert_equal 0, @server.requests.size
  end

  def test_legacy_create_list_names_its_replacement_and_keeps_its_contract
    out, err, status = planka("--help", executable: "planka-create-list")
    assert status.success?, err
    assert_includes out, "planka create list --board BOARD --name NAME"
    out, err, status = planka("create-list", "--name", "Legacy", "--output", "json", env: { "PLANKA_BOARD_ID" => BOARD })
    assert status.success?, err
    created = @server.lists.last
    assert_equal({ "list" => { "id" => created["id"], "boardId" => BOARD, "name" => "Legacy", "type" => "active", "position" => 131_072.0 },
                   "created" => true }, JSON.parse(out))
    _out, err, status = planka("create-list", "--name", "Legacy", "--type", "archive", env: { "PLANKA_BOARD_ID" => BOARD })
    assert_equal 1, status.exitstatus
    assert_match(/type must be one of active, closed/, err)
  end
end
