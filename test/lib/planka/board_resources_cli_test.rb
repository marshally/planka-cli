require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_project_boards"

class BoardResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  BOARD = FakePlanka::BOARD_ID
  PROJECT = FakeProjectBoards::PROJECT_ID
  OTHER_PROJECT = FakeProjectBoards::OTHER_PROJECT

  def setup = @server = FakeProjectBoards.new
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

  def expected_board(overrides = {})
    { "id" => BOARD, "projectId" => PROJECT, "name" => "Development", "position" => 65_536,
      "createdAt" => "2026-10-01T00:00:00.000Z", "updatedAt" => nil,
      "url" => "#{@server.base_url}/boards/#{BOARD}" }.merge(overrides)
  end

  def test_describe_and_legacy_snapshot_keep_their_existing_shapes_and_direct_parity
    flat, flat_err, flat_status = planka("snapshot", "-o", "json", env: { "PLANKA_BOARD_ID" => BOARD })
    direct, direct_err, direct_status = planka("-o", "json", executable: "planka-snapshot", env: { "PLANKA_BOARD_ID" => BOARD })
    assert flat_status.success?, flat_err
    assert_equal [flat, flat_err, flat_status.exitstatus], [direct, direct_err, direct_status.exitstatus]
    snapshot = JSON.parse(flat)
    assert_equal BOARD, snapshot["boardId"]
    refute snapshot.key?("meta")
    described, err, status = json("describe", "board", BOARD)
    assert status.success?, err
    assert_equal snapshot, described["data"]
    assert_equal({}, described["meta"])
    legacy, err, status = planka("snapshot", env: { "PLANKA_BOARD_ID" => BOARD })
    assert status.success?, err
    out, err, status = planka("describe", "boards", BOARD)
    assert status.success?, err
    assert_equal legacy, out
    assert_empty writes
  end

  def test_failed_project_reads_are_incomplete_and_do_not_authorize_creation
    [403, 404, :drop, { "item" => nil }, { "item" => { "id" => OTHER_PROJECT }, "included" => { "boards" => [] } },
     { "item" => { "id" => PROJECT }, "included" => { "boards" => nil } }].each do |failure|
      @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, failure)
      doc, err, status = json("get", "boards", "--project", PROJECT)
      assert_equal 1, status.exitstatus, err
      assert_equal({ "data" => [], "meta" => { "complete" => false } }, doc.slice("data", "meta"))
      @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, failure)
      doc, err, status = json("create", "board", "--project", PROJECT, "--name", "X")
      assert_equal [1, false], [status.exitstatus, doc.dig("meta", "changed")], err
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
    assert_empty writes
  end

  def test_malformed_write_confirmations_cannot_claim_success
    [{ "item" => nil }, { "item" => expected_board("id" => "999") },
     { "item" => expected_board("projectId" => OTHER_PROJECT) }, { "item" => expected_board("position" => nil) }].each do |payload|
      [["PATCH", ["update", "board", BOARD, "--name", "X"], "name"], ["DELETE", ["delete", "board", BOARD], "deleted"]].each do |method, args, field|
        @server.requests.clear
        @server.inject(method, %r{/api/boards/#{BOARD}\z}, payload)
        doc, err, status = json(*args)
        assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")], err
        assert_nil doc.dig("data", field)
        assert_equal BOARD, doc.dig("data", "id")
        assert_equal "readback-board", doc.dig("error", "recovery", "action")
        assert_equal 1, writes.size
      end
    end
  end

  def test_native_normalized_positions_are_reported_and_unsupplied_fields_are_preserved
    @server.inject("PATCH", %r{/api/boards/#{BOARD}\z}, { "item" => expected_board("position" => 16_384) })
    doc, err, status = json("update", "board", BOARD, "--position", "0")
    assert status.success?, err
    assert_equal expected_board("position" => 16_384), doc["data"]
    assert_equal [["PATCH", "/api/boards/#{BOARD}", { "position" => 0 }]], writes
    doc, err, status = json("create", "board", "--project", OTHER_PROJECT, "--name", "😀" * 64)
    assert status.success?, err
    assert_equal 65_536, doc.dig("data", "position")
    assert_equal "😀" * 64, doc.dig("data", "name")
  end

  def test_help_is_offline_at_every_level_and_explains_native_effects_and_recovery
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    [[], ["get"], ["create"], ["update"], ["delete"]].each do |path|
      out, err, status = planka(*path, "--help", env: offline)
      assert status.success?, err
      assert_includes out, "board"
    end
    %w[get create update delete].each do |verb|
      out, err, status = planka(verb, "boards", "--help", env: offline)
      assert status.success?, err
      assert_includes out, "Example: planka #{verb}"
      assert_includes out, "project"
      assert_includes out, "data"
      assert_includes out, "human"
    end
    out, _err, _status = planka("create", "board", "--help", env: offline)
    assert_includes out, "editor membership"
    assert_includes out, "archive and trash"
    assert_includes out, "readback-boards"
    out, _err, _status = planka("delete", "board", "--help", env: offline)
    assert_includes out, "lists, cards, labels, and memberships"
    assert_includes out, "readback-board"
    assert_empty @server.requests
  end

  def test_malformed_individual_reads_cannot_authorize_a_mutation
    [{ "id" => "999" }, { "projectId" => "../projects/1" }, { "name" => nil }, { "position" => nil },
     { "createdAt" => false }].each do |change|
      @server.inject("GET", %r{/api/boards/#{BOARD}\z}, { "item" => expected_board(change), "included" => {} })
      doc, err, status = json("update", "board", BOARD, "--name", "X")
      assert_equal [1, "api_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")], err
      assert_nil doc["data"]
    end
    assert_empty writes
  end

  def test_rejected_writes_preserve_observed_state_and_cleanup_cannot_mask_the_failure
    [["POST", %r{/api/projects/.+/boards\z}, ["create", "board", "--project", PROJECT, "--name", "X"]],
     ["PATCH", %r{/api/boards/\d+\z}, ["update", "board", BOARD, "--name", "X"]],
     ["DELETE", %r{/api/boards/\d+\z}, ["delete", "board", BOARD]]].each do |method, route, args|
      @server.requests.clear
      @server.inject(method, route, 403)
      @server.inject("DELETE", %r{access-tokens/me\z}, 500)
      doc, err, status = json(*args)
      assert_equal [1, "authorization_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")], err
      method == "POST" ? assert_nil(doc.dig("data", "id")) : assert_equal(expected_board, doc["data"])
      assert_equal 1, writes.size
      assert_includes err, "session cleanup failed"
      refute_includes err, "private upstream body"
      refute_includes err, "fake-password"
      refute_includes err, "fake-token"
    end
    @server.inject("DELETE", %r{access-tokens/me\z}, 500)
    doc, err, status = json("update", "board", BOARD, "--name", "Changed")
    assert status.success?, err
    assert_equal true, doc.dig("meta", "changed")
    assert_equal "Changed", doc.dig("data", "name")
    assert_includes err, "session cleanup failed"
  end

  def test_dropped_writes_preserve_uncertainty_and_require_readback_without_retries
    [["POST", "/api/projects/#{PROJECT}/boards", ["create", "board", "--project", PROJECT, "--name", "Review"], "readback-boards", "name"],
     ["PATCH", "/api/boards/#{BOARD}", ["update", "board", BOARD, "--name", "Delivery"], "readback-board", "name"],
     ["DELETE", "/api/boards/#{BOARD}", ["delete", "board", BOARD], "readback-board", "deleted"]].each do |method, path, args, recovery, uncertain|
      @server.requests.clear
      @server.inject(method, /\A#{Regexp.escape(path)}\z/, :apply_then_drop)
      doc, err, status = json(*args)
      assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")], err
      assert_nil doc.dig("data", uncertain)
      assert_equal PROJECT, doc.dig("data", "projectId")
      assert_equal recovery, doc.dig("error", "recovery", "action")
      method == "POST" ? assert_nil(doc.dig("data", "id")) : assert_equal(BOARD, doc.dig("data", "id"))
      assert_equal 1, writes.size
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
    doc, err, status = json("get", "boards", "--project", PROJECT, "--name", "Review")
    assert status.success?, err
    assert_equal ["Review"], doc["data"].map { |board| board["name"] }, "the uncertain create can be reconciled through the public read"
  end

  def test_malformed_collections_retain_validated_matching_results_and_fail_even_after_the_limit
    [nil, expected_board("id" => "bad"), expected_board("projectId" => OTHER_PROJECT),
     expected_board("name" => 42), expected_board("position" => -1), expected_board("updatedAt" => "bad"),
     expected_board].each do |bad|
      records = [expected_board, expected_board("id" => "101", "name" => "Other", "position" => 1), bad]
      @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, { "item" => { "id" => PROJECT }, "included" => { "boards" => records } })
      doc, err, status = json("get", "boards", "--project", PROJECT, "--name", "Development", "--limit", "1")
      assert_equal [1, "api_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "complete")], err
      assert_equal [expected_board], doc["data"]
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
    assert_empty writes
  end

  def test_local_input_and_missing_configuration_fail_before_any_request
    invalid = [["get", "boards"], ["get", "board", "Development"], ["get", "boards", "--project", "a name"],
               ["get", "boards", "--project", PROJECT, "--limit", "0"],
               ["get", "boards", "--project", PROJECT, "--name", "A", "--name", "B"],
               ["get", "boards", "--project", PROJECT, "--label", "enhancement"],
               ["get", "boards", "--project", PROJECT, "--member", "ada"],
               ["get", "board", BOARD, "--name", "Development"], ["get", "board", BOARD, "--limit", "1"],
               ["create", "board", "--name", "X"], ["create", "board", "--project", PROJECT],
               ["create", "board", BOARD, "--project", PROJECT, "--name", "X"],
               ["update", "board", BOARD], ["update", "board", BOARD, "--project", PROJECT],
               ["update", "board", BOARD, "--default-view", "grid"], ["delete", "board"],
               ["delete", "board", BOARD, "--cascade"], ["delete", "board", BOARD, "--yes"],
               ["get", "board", "https://elsewhere.test/boards/#{BOARD}"],
               ["get", "boards", "--project", "#{@server.base_url}/projects/#{PROJECT}?x=1"]]
    ["", " ", "x" * 129, "😀" * 65].each do |name|
      invalid << ["create", "board", "--project", PROJECT, "--name", name]
      invalid << ["update", "board", BOARD, "--name", name]
    end
    %w[-1 NaN Infinity 1e309 nope].each do |position|
      invalid << ["create", "board", "--project", PROJECT, "--name", "X", "--position", position]
      invalid << ["update", "board", BOARD, "--position", position]
    end
    invalid.each do |args|
      doc, err, status = json(*args, env: { "PLANKA_BOARD_ID" => BOARD })
      assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], "#{args.inspect}: #{err}"
    end
    %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].each do |setting|
      [["get", "boards", "--project", PROJECT], ["get", "board", BOARD],
       ["create", "board", "--project", PROJECT, "--name", "X"], ["update", "board", BOARD, "--name", "X"],
       ["delete", "board", BOARD]].each do |args|
        doc, err, status = json(*args, env: { setting => nil })
        assert_equal [1, "configuration_error"], [status.exitstatus, doc.dig("error", "code")], err
      end
    end
    assert_empty @server.requests
  end

  def test_malformed_create_preserves_a_new_returned_id_for_readback_without_retrying
    @server.inject("POST", %r{/api/projects/.+/boards\z}, { "item" => { "id" => "901" } })
    doc, err, status = json("create", "board", "--project", PROJECT, "--name", "Review")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")], err
    assert_equal "901", doc.dig("data", "id")
    assert_equal PROJECT, doc.dig("data", "projectId")
    assert_equal "#{@server.base_url}/boards/901", doc.dig("data", "url")
    assert_equal({ "action" => "readback-board", "resources" => [{ "type" => "project", "id" => PROJECT }, { "type" => "board", "id" => "901" }] }, doc.dig("error", "recovery"))
    assert_equal 1, writes.size
    @server.inject("POST", %r{/api/projects/.+/boards\z}, { "item" => expected_board })
    doc, err, status = json("create", "board", "--project", PROJECT, "--name", "Development")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("data", "id")], err
    assert_equal "readback-boards", doc.dig("error", "recovery", "action"), "a reused ID is not a created identity"
  end

  def test_delete_issues_only_the_target_delete_and_the_board_is_no_longer_readable
    doc, err, status = json("delete", "boards", "Development", "--project", PROJECT)
    assert status.success?, err
    assert_equal({ "data" => expected_board("deleted" => true), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["DELETE", "/api/boards/#{BOARD}", nil]], writes
    read, err, status = json("get", "board", BOARD)
    assert_equal [1, "not_found"], [status.exitstatus, read.dig("error", "code")], err
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_update_changes_only_supplied_fields_and_skips_identical_writes
    doc, err, status = json("update", "boards", BOARD, "--name", "Delivery")
    assert status.success?, err
    assert_equal({ "data" => expected_board("name" => "Delivery"), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["PATCH", "/api/boards/#{BOARD}", { "name" => "Delivery" }]], writes
    @server.requests.clear
    out, err, status = planka("update", "board", "Delivery", "--project", PROJECT, "--position", "10", "--name", "Delivery")
    assert status.success?, err
    assert_equal "Updated board Delivery (#{BOARD}) on project #{PROJECT}: #{@server.base_url}/boards/#{BOARD}\n", out
    assert_equal [["PATCH", "/api/boards/#{BOARD}", { "position" => 10 }]], writes
    @server.requests.clear
    doc, err, status = json("update", "board", BOARD, "--position", "10", "--name", "Delivery")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_equal expected_board("name" => "Delivery", "position" => 10), doc["data"]
    assert_empty writes
    read, err, status = json("get", "board", BOARD)
    assert status.success?, err
    assert_equal doc["data"], read["data"]
  end

  def test_create_appends_after_the_projects_boards_and_can_be_read_back
    @server.add_project_board("101", "Later", position: 131_072)
    @server.add_project_board("102", "Elsewhere", position: 999_999, project_id: OTHER_PROJECT)
    doc, err, status = json("create", "board", "--project", PROJECT, "--name", "Development")
    assert status.success?, err
    id = doc.dig("data", "id")
    refute_equal BOARD, id, "create never reuses an exact-name board"
    assert_equal expected_board("id" => id, "position" => 196_608, "url" => "#{@server.base_url}/boards/#{id}"), doc["data"]
    assert_equal({ "changed" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_equal [["POST", "/api/projects/#{PROJECT}/boards", { "name" => "Development", "position" => 196_608 }]], writes
    read, err, status = json("get", "board", id)
    assert status.success?, err
    assert_equal doc["data"], read["data"]
    out, err, status = planka("create", "boards", "--project", OTHER_PROJECT, "--name", "Ünicode", "--position", "0.5")
    assert status.success?, err
    assert_match(/Created board Ünicode \(\d+\)/, out)
    assert_equal ["POST", "/api/projects/#{OTHER_PROJECT}/boards", { "name" => "Ünicode", "position" => 0.5 }], writes.last
  end

  def test_unknown_ambiguous_and_mismatched_boards_fail_without_writes
    @server.add_project_board("101", "Development", position: 1)
    doc, err, status = json("get", "board", "Development", "--project", PROJECT)
    assert_equal [1, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], err
    assert_includes doc.dig("error", "message"), BOARD
    assert_includes doc.dig("error", "message"), "101"
    [["Missing", "--project", PROJECT], ["999"]].each do |args|
      doc, err, status = json("get", "board", *args)
      assert_equal [1, "not_found"], [status.exitstatus, doc.dig("error", "code")], err
    end
    doc, err, status = json("get", "board", BOARD, "--project", OTHER_PROJECT)
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], err
    assert_includes doc.dig("error", "message"), "does not belong to --project"
    assert_empty writes
  end

  def test_individual_reads_use_id_url_or_an_exact_name_in_the_explicit_project
    [[BOARD], ["#{@server.base_url}/boards/#{BOARD}"], ["Development", "--project", PROJECT]].each do |args|
      doc, err, status = json("get", "board", *args, env: { "PLANKA_BOARD_ID" => "999" })
      assert status.success?, err
      assert_equal({ "data" => expected_board, "meta" => {}, "error" => nil }, doc)
    end
    out, err, status = planka("get", "boards", BOARD, "--project", PROJECT)
    assert status.success?, err
    assert_equal "Development (#{BOARD}) on project #{PROJECT}: #{@server.base_url}/boards/#{BOARD}\n", out
    assert_empty writes
  end

  def test_exact_name_filters_precede_limits_and_report_matching_completeness
    @server.add_project_board("103", "Development", position: 131_072)
    @server.add_project_board("101", "Other", position: 1)
    doc, err, status = json("get", "boards", "--project", PROJECT, "--name", "Development", "--limit", "1")
    assert status.success?, err
    assert_equal [expected_board], doc["data"]
    assert_equal false, doc.dig("meta", "complete")
    doc, err, status = json("get", "board", "--project", "#{@server.base_url}/projects/#{PROJECT}", "--name", "Development", "--limit", "2")
    assert status.success?, err
    assert_equal([BOARD, "103"], doc["data"].map { |board| board["id"] })
    assert_equal true, doc.dig("meta", "complete")
    out, err, status = planka("get", "boards", "--project", PROJECT, "--limit", "1")
    assert status.success?, err
    assert_includes out, "Results truncated"
    doc, err, status = json("get", "boards", "--project", PROJECT, "--name", "development")
    assert status.success?, err
    assert_equal({ "data" => [], "meta" => { "complete" => true }, "error" => nil }, doc)
    out, err, status = planka("get", "boards", "--project", OTHER_PROJECT)
    assert status.success?, err
    assert_equal "No boards.\n", out
    assert_empty writes
  end

  def test_collection_reads_only_the_explicit_project_in_position_order
    @server.add_project_board("103", "Later", position: 131_072)
    @server.add_project_board("101", "First", position: 1)
    @server.add_project_board("102", "Elsewhere", position: 0, project_id: OTHER_PROJECT)
    doc, err, status = json("get", "boards", "--project", PROJECT)
    assert status.success?, err
    assert_equal(["101", BOARD, "103"], doc["data"].map { |board| board["id"] })
    assert_equal expected_board, doc["data"][1]
    assert_equal({ "complete" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_equal([["POST", "/api/access-tokens"], ["GET", "/api/projects/#{PROJECT}"],
                  ["DELETE", "/api/access-tokens/me"]], @server.requests.map { |request| request.first(2) })
    assert_empty writes
  end
end
