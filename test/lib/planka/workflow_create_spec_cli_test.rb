require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class WorkflowCreateSpecCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  BOARD = FakePlanka::BOARD_ID
  READY = FakePlanka::LIST_READY
  CARD = FakePlanka::PARENT_CARD

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, stdin: "", executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-spec-password", "PLANKA_BOARD_ID" => nil }
    out, err, status = Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args,
                                      chdir: Dir.tmpdir, stdin_data: stdin)
    [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status]
  end

  def writes
    @server.requests.reject { |method, path, _| method == "GET" || path.include?("access-tokens") }
           .map { |method, path, body| [method, path, JSON.parse(body)] }
  end

  def test_creates_an_appended_project_spec_on_a_story_board_and_preserves_stdin
    @server.boards.first["defaultCardType"] = "story"
    @server.add_card("Below", READY, position: 131_072)
    text = "Ünïcode \"quoted\"\nsecond line\n"
    doc, err, status = json("workflow", "create", "spec", "--list", "ready-for-agent", "--board", "#{@server.base_url}/boards/#{BOARD}",
                            "--name", "Search", "--description-file", "-", stdin: text)
    assert status.success?, err
    assert_equal %w[data meta error], doc.keys
    assert_equal({ "changed" => true }, doc["meta"])
    assert_nil doc["error"]
    card = doc["data"]
    assert_match(/\A\d+\z/, card["id"])
    assert_equal ["Search", text, "project", BOARD, READY, 196_608],
                 card.values_at("name", "description", "type", "boardId", "listId", "position")
    assert_equal [["POST", "/api/lists/#{READY}/cards", { "type" => "project", "name" => "Search", "position" => 196_608, "description" => text }]], writes
    assert_empty @server.task_lists
    assert_empty @server.tasks
    assert_empty @server.memberships
    readback, err, status = json("get", "card", card["id"])
    assert status.success?, err
    assert_equal card, readback["data"]
    assert_equal 1, writes.size, "readback does not write resources"
  end

  def test_nested_help_is_offline_and_names_only_supported_spec_creation
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    { ["--help"] => "workflow create spec --list LIST --name NAME",
      ["workflow", "--help"] => "create spec --list LIST --name NAME",
      ["workflow", "create", "--help"] => "usage: planka workflow create <resource> [flags]",
      ["workflow", "create", "spec", "--help"] => "usage: planka workflow create spec --list LIST",
      ["workflow", "create", "specs", "-h"] => "spec/specs are aliases" }.each do |args, expected|
      out, err, status = planka(*args, env: offline)
      assert status.success?, err
      assert_empty err
      assert_includes out, expected
      refute_includes out, "workflow create ticket"
    end
    assert_empty @server.requests
  end

  def test_malformed_create_preserves_a_returned_numeric_identity_for_readback
    id = "1900000000000000099"
    @server.inject("POST", %r{/api/lists/.+/cards\z}, { "item" => { "id" => id } })
    doc, _err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Search")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal [id, BOARD, READY, nil, nil], doc["data"].values_at("id", "boardId", "listId", "name", "type")
    assert_equal({ "action" => "readback-card", "resources" => [{ "type" => "card", "id" => id }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_a_create_response_cannot_confirm_an_already_observed_card_as_a_new_spec
    existing = @server.find_card(CARD).merge("name" => "Search", "description" => nil, "position" => 131_072)
    @server.inject("POST", %r{/api/lists/.+/cards\z}, { "item" => existing })
    doc, _err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Search")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_nil doc.dig("data", "id")
    assert_equal({ "action" => "readback-cards", "resources" => [{ "type" => "list", "id" => READY }] }, doc.dig("error", "recovery"))
    assert_equal 1, writes.size
  end

  def test_alias_file_input_positions_and_duplicate_names_always_create_new_specs
    Dir.mktmpdir do |dir|
      path = File.join(dir, "description.md")
      text = "Café \"search\"\nfinal newline\n"
      File.write(path, text)
      out, err, status = planka("-o", "json", "workflow", "create", "specs", "--list", "#{@server.base_url}/lists/#{READY}",
                                "--name", "Repeat", "--position", "0", "--description-file", path,
                                env: { "PLANKA_BOARD_ID" => "invalid-default", "LC_ALL" => "C", "LANG" => "C" })
      assert status.success?, err
      first = JSON.parse(out)["data"]
      assert_equal ["Repeat", text, 0, BOARD, READY], first.values_at("name", "description", "position", "boardId", "listId")
      doc, err, status = json("workflow", "-o", "json", "create", "spec", "--list", READY, "--name", "Repeat", "--position", "1.5")
      assert status.success?, err
      assert_equal ["Repeat", nil, 1.5], doc["data"].values_at("name", "description", "position")
      refute_equal first["id"], doc.dig("data", "id")
      assert_equal 2, writes.size
      refute writes.last.last.key?("description")
    end
  end

  def test_invalid_invocations_and_local_files_fail_before_any_request
    Dir.mktmpdir do |dir|
      empty = File.join(dir, "empty.md")
      invalid = File.join(dir, "invalid.md")
      File.write(empty, "")
      File.binwrite(invalid, "\xFF\xFE")
      [["--name", "Missing list"], ["--list", READY], ["--list", READY, "--name", ""],
       ["--list", READY, "--name", "x" * 1025], ["--list", READY, "--name", "😀" * 513],
       ["--list", READY, "--name", "x", "--position", "-1"], ["--list", READY, "--name", "x", "--position", "Infinity"],
       ["--list", READY, "--name", "x", "--name", "y"], ["--list", READY, "--title", "x"],
       ["extra", "--list", READY, "--name", "x"], ["--list", READY, "--name", "x", "--criteria-file", "-"],
       ["--list", READY, "--name", "x", "--description-file", empty],
       ["--list", READY, "--name", "x", "--description-file", invalid],
       ["--list", READY, "--name", "x", "--description-file", File.join(dir, "missing.md")],
       ["--list", "https://other.example/lists/123", "--name", "x"]].each do |suffix|
        doc, err, status = json("-o", "json", "workflow", "create", "spec", *suffix)
        assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], suffix.inspect
        refute_includes err, "fake-spec-password"
        refute_includes err, "card_input.rb"
      end
    end
    assert_empty @server.requests
  end

  def test_ambiguous_list_names_are_operational_failures_with_candidate_ids
    duplicate = @server.add_list("ready-for-agent")
    doc, err, status = json("workflow", "create", "spec", "--list", "ready-for-agent", "--name", "Search",
                            env: { "PLANKA_BOARD_ID" => BOARD })
    assert_equal [1, "invalid_input", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_includes err, READY
    assert_includes err, duplicate
    assert_empty writes
  end

  def test_legacy_create_spec_help_names_the_replacement_and_keeps_bare_json_and_flags
    dispatched, err, status = planka("create-spec", "--help")
    assert status.success?, err
    assert_includes dispatched, "planka workflow create spec --list LIST --name NAME"
    direct, err, status = planka("--help", executable: "planka-create-spec")
    assert status.success?, err
    assert_equal dispatched, direct
    @server.boards.first["defaultCardType"] = "story"
    [["planka", ["create-spec"]], ["planka-create-spec", []]].each do |executable, prefix|
      out, err, status = planka(*prefix, "--list", "ready-for-agent", "--board", BOARD, "--title", "Legacy spec",
                                "--description-file", "-", "--position", "3", "--output", "json", executable: executable, stdin: "Legacy\ntext\n")
      assert status.success?, err
      assert_empty err
      doc = JSON.parse(out)
      assert_equal ["card"], doc.keys
      assert_equal %w[id name url], doc["card"].keys
      id = doc.dig("card", "id")
      assert_equal "#{@server.base_url}/cards/#{id}", doc.dig("card", "url")
      assert_equal ["project", "Legacy\ntext\n", 3], @server.find_card(id).values_at("type", "description", "position")
    end
    assert_equal 2, writes.size
    assert_empty @server.task_lists
  end

  def test_configuration_and_parent_scope_failures_do_not_publish
    [[{ "PLANKA_AGENT_PASSWORD" => nil }, ["--list", READY], "configuration_error", 1],
     [{ "PLANKA_BASE_URL" => "invalid" }, ["--list", READY], "configuration_error", 1],
     [{ "PLANKA_BOARD_ID" => "invalid" }, ["--list", "ready-for-agent"], "configuration_error", 1],
     [{}, ["--list", "missing", "--board", BOARD], "not_found", 1],
     [{}, ["--list", READY, "--board", "999"], "invalid_input", 2]].each do |env, flags, code, exit|
      doc, err, status = json("workflow", "create", "spec", "--name", "Search", *flags, env: env)
      assert_equal [exit, code, false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
      refute_includes err, "fake-spec-password"
    end
    assert_empty writes
    assert_equal 2, @server.counts("POST", %r{access-tokens\z}), "only API-dependent scope failures authenticate"
  end

  def test_human_output_and_archive_placement_follow_native_rules
    out, err, status = planka("workflow", "create", "spec", "--list", "ready-for-agent", "--name", "Human spec",
                              env: { "PLANKA_BOARD_ID" => BOARD })
    assert status.success?, err
    assert_empty err
    assert_equal "Created spec Human spec (#{@server.cards.last["id"]}) in list #{READY}\n", out
    archive = @server.add_list(nil, "archive")
    doc, err, status = json("workflow", "create", "spec", "--list", archive, "--board", BOARD, "--name", "Archived spec")
    assert status.success?, err
    assert_equal ["project", archive, nil], doc["data"].values_at("type", "listId", "position")
    assert_equal ["POST", "/api/lists/#{archive}/cards", { "type" => "project", "name" => "Archived spec" }], writes.last
    doc, _err, status = json("workflow", "create", "spec", "--list", archive, "--board", BOARD, "--name", "Invalid", "--position", "5")
    assert_equal [2, "invalid_input", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal 2, writes.size
  end

  def test_authentication_read_and_rejected_write_failures_preserve_unchanged_effects
    [["POST", %r{/api/access-tokens\z}, 401, "authentication_error"],
     ["GET", %r{/api/boards/}, :server_error, "api_error"],
     ["GET", %r{/api/boards/}, { "item" => { "id" => BOARD, "defaultCardType" => "project" }, "included" => { "lists" => nil } }, "api_error"],
     ["POST", %r{/api/lists/.+/cards\z}, 403, "authorization_error"],
     ["POST", %r{/api/lists/.+/cards\z}, 400, "api_error"]].each do |method, path, fault, code|
      @server.inject(method, path, fault)
      doc, err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Search")
      assert_equal [1, code, false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
      assert_nil doc.dig("data", "id")
      refute_includes err, "fake-spec-password"
      refute_includes err, "private upstream body"
    end
    assert_equal 2, writes.size
    assert_equal([CARD], @server.cards.map { |card| card["id"] })
    assert_empty @server.task_lists
  end

  def test_unknown_create_is_not_retried_and_readback_can_reconcile_the_spec
    @server.inject("POST", %r{/api/lists/.+/cards\z}, :apply_then_drop)
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 403)
    doc, err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Uncertain")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal [nil, BOARD, READY, nil, nil], doc["data"].values_at("id", "boardId", "listId", "name", "type")
    assert_equal({ "action" => "readback-cards", "resources" => [{ "type" => "list", "id" => READY }] }, doc.dig("error", "recovery"))
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    assert_includes err, "Mutation outcome is unknown"
    assert_equal 1, writes.size
    recovered, err, status = json("get", "cards", "--list", READY, "--name", "Uncertain")
    assert status.success?, err
    assert_equal(["project"], recovered["data"].map { |card| card["type"] })
    assert_equal 1, writes.size
  end

  def test_missing_or_untrusted_write_identities_remain_unknown_and_never_leak_raw_data
    [:malformed_auth, { "included" => {} }, { "item" => nil }, { "item" => { "id" => "../unsafe-secret" } }].each do |fault|
      @server.inject("POST", %r{/api/lists/.+/cards\z}, fault)
      doc, err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Search")
      assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
      assert_nil doc.dig("data", "id")
      assert_equal "readback-cards", doc.dig("error", "recovery", "action")
      refute_includes JSON.generate(doc) + err, "unsafe-secret"
      refute_includes err, "KeyError"
    end
    assert_equal 4, writes.size
    assert_empty @server.task_lists
  end

  def test_the_offline_guide_names_spec_creation_and_stays_within_its_word_limit
    doc, err, status = json("workflow", "guide", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert status.success?, err
    text = doc.dig("data", "instructions")
    assert_includes text, "planka workflow create spec --list LIST --name NAME"
    assert_operator text.split.size, :<=, 500
    refute_includes text, "planka workflow create ticket"
    assert_empty @server.requests
  end

  def test_a_negative_returned_position_cannot_confirm_the_create
    id = "1900000000000000099"
    invalid = @server.find_card(CARD).merge("id" => id, "name" => "Search", "description" => nil, "position" => -1)
    @server.inject("POST", %r{/api/lists/.+/cards\z}, { "item" => invalid })
    doc, _err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Search")
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal id, doc.dig("data", "id")
    assert_nil doc.dig("data", "position")
    assert_equal "readback-card", doc.dig("error", "recovery", "action")
  end

  def test_cleanup_failure_preserves_success_and_a_rejected_write
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 403)
    doc, err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Confirmed")
    assert status.success?, err
    assert_equal({ "changed" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    @server.inject("POST", %r{/api/lists/.+/cards\z}, 403)
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 403)
    doc, err, status = json("workflow", "create", "spec", "--list", READY, "--name", "Rejected")
    assert_equal [1, "authorization_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    assert_equal 2, writes.size
  end
end
