require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"
require_relative "../../../lib/planka/workflow"
require_relative "../../../lib/planka/client"

# Drives the publishing commands end to end over HTTP against an in-memory
# Planka, through the same exe/planka entry point an operator would run. No live
# board, no real credentials.
class Planka::PublishingCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  PARENT = FakePlanka::PARENT_CARD
  PASSWORD = "p@ss-do-not-leak-7f3".freeze

  def setup
    @server = FakePlanka.new
  end

  def teardown
    @server.stop
  end

  def planka(*args, env: {}, stdin: nil)
    base = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
      "PLANKA_AGENT_PASSWORD" => PASSWORD, "PLANKA_BOARD_ID" => @server.board_id }
    opts = { chdir: Dir.tmpdir }
    opts[:stdin_data] = stdin if stdin
    Open3.capture3(base.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, **opts)
  end

  def planka_executable(command, *args)
    base = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
      "PLANKA_AGENT_PASSWORD" => PASSWORD, "PLANKA_BOARD_ID" => @server.board_id }
    Open3.capture3(base, RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka-#{command}", *args, chdir: Dir.tmpdir)
  end

  def ok(*args, **kwargs)
    out, err, status = planka(*args, **kwargs)
    assert status.success?, "#{args.inspect} failed (#{err})"
    out
  end

  def ok_json(*args, **kwargs) = JSON.parse(ok(*args, "--output", "json", **kwargs))

  def file(name, content)
    path = File.join(Dir.mktmpdir, name)
    File.write(path, content)
    path
  end

  def with_client
    client = Planka::Client.new(@server.base_url)
    client.sign_in("bot@example.com", PASSWORD)
    yield client
  ensure
    client&.sign_out
  end

  def test_describe_board_preserves_snapshot_data_and_human_output_without_writes
    board = FakePlanka::BOARD_ID
    out, err, status = planka("describe", "board", board, "-o", "json",
      env: { "PLANKA_BOARD_ID" => "999999" })
    assert status.success?, err
    assert_empty err
    document = JSON.parse(out)
    assert_equal ["data", "error", "meta"], document.keys.sort
    assert_equal({}, document["meta"])
    assert_nil document["error"]
    data = document["data"]
    assert_equal board, data["boardId"]
    assert_equal %w[boardId cardLabels cardMemberships cards labels lists taskLists tasks], data.keys.sort
    assert_equal [PARENT], data["cards"].map { |card| card["id"] }
    assert_equal "#{@server.base_url}/cards/#{PARENT}", data["cards"].first["url"]
    assert_equal %w[ready-for-agent in-progress done], data["lists"].map { |list| list["name"] }
    assert_empty data["tasks"]
    assert_equal [ ["POST", "/api/access-tokens"], ["GET", "/api/boards/#{board}"],
      ["DELETE", "/api/access-tokens/me"] ], @server.requests.map { |m, p, _| [m, p] }
    assert_equal ok_json("snapshot", "--board", board), data
    direct, direct_err, direct_status = planka_executable("snapshot", "--board", board, "--output", "json")
    assert direct_status.success?, direct_err
    assert_equal data, JSON.parse(direct)
    assert_equal ok("snapshot", "--board", board), ok("describe", "board", board)
  end

  def test_describe_board_urls_aliases_and_common_flags_use_explicit_instance
    board = FakePlanka::BOARD_ID
    url = "#{@server.base_url}/boards/#{board}/"
    [ ["-o", "json", "describe", "board", url],
      ["describe", "--output", "json", "boards", board],
      ["describe", "boards", "-o", "json", board] ].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_BOARD_ID" => nil })
      assert status.success?, err
      assert_empty err
      assert_equal board, JSON.parse(out).dig("data", "boardId")
    end
    @server.requests.clear
    ["https://other.example/boards/#{board}", "#{@server.base_url}/cards/#{PARENT}",
      "http://[bad]/boards/123"].each do |reference|
      out, err, status = planka("describe", "board", reference, "-o", "json")
      assert_equal 2, status.exitstatus
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
      assert_match(/\Aplanka describe board:/, err)
      assert_empty @server.requests
    end
  end

  def test_board_cleanup_failure_keeps_the_read_result_and_names_the_board_command
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("describe", "board", FakePlanka::BOARD_ID, "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal FakePlanka::BOARD_ID, JSON.parse(out).dig("data", "boardId")
    assert_includes err, "planka describe board: session cleanup failed"
    refute_includes err, "private upstream body"
  end

  def test_board_invalid_invocations_do_not_authenticate_or_fall_back_to_environment
    [ ["describe", "board"], ["describe", "board", "Ready"],
      ["describe", "board", FakePlanka::BOARD_ID, "--unknown"],
      ["describe", "board", FakePlanka::BOARD_ID, "--board", FakePlanka::BOARD_ID],
      ["describe", "board", FakePlanka::BOARD_ID, "extra"] ].each do |args|
      out, err, status = planka("-o", "json", *args)
      assert_equal 2, status.exitstatus
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
      refute_includes err, "describe card"
      assert_empty @server.requests
    end
  end

  def test_board_description_does_not_report_malformed_snapshot_as_success
    @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, :malformed_board)
    out, err, status = planka("describe", "board", FakePlanka::BOARD_ID, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    assert_match(/\Aplanka describe board:/, err)
    refute_includes err, "canonical_cli.rb"
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_board_description_configuration_checks_precede_network_and_api_errors_are_sanitized
    %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].each do |key|
      [nil, ""].each do |value|
        out, err, status = planka("describe", "board", FakePlanka::BOARD_ID, "-o", "json", env: { key => value })
        assert_equal 1, status.exitstatus
        assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
        assert_includes err, key
        assert_empty @server.requests
      end
    end
    @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, 404)
    out, err, status = planka("describe", "board", FakePlanka::BOARD_ID, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "not_found", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    assert_match(/\Aplanka describe board:/, err)
    refute_includes out + err, "private upstream body"
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_describe_card_wraps_legacy_detail_and_only_reads_resources
    out, err, status = planka("describe", "card", PARENT, "-o", "json",
      env: { "PLANKA_BOARD_ID" => nil })
    assert status.success?, err
    assert_empty err
    document = JSON.parse(out)
    assert_equal ["data", "error", "meta"], document.keys.sort
    assert_equal({}, document["meta"])
    assert_nil document["error"]
    assert_equal PARENT, document["data"]["id"]
    assert_equal "Original description.", document["data"]["description"]
    assert_equal "ready-for-agent", document["data"]["listName"]
    assert_equal ["Parent context note."], document["data"]["comments"].map { |c| c["text"] }
    assert_equal [ ["POST", "/api/access-tokens"], ["GET", "/api/cards/#{PARENT}"],
      ["GET", "/api/boards/#{FakePlanka::BOARD_ID}"], ["GET", "/api/cards/#{PARENT}/comments"],
      ["DELETE", "/api/access-tokens/me"] ], @server.requests.map { |m, p, _| [m, p] }
    assert_equal ok_json("show", PARENT), document["data"]
    direct, direct_err, direct_status = planka_executable("show", PARENT, "--output", "json")
    assert direct_status.success?, direct_err
    assert_equal document["data"], JSON.parse(direct)
    assert_equal ok("show", PARENT), ok("describe", "card", PARENT)
  end

  def test_describe_validates_all_required_environment_before_network_access
    %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].each do |key|
      [nil, "", "  "].each do |value|
        out, err, status = planka("describe", "card", PARENT, "-o", "json", env: { key => value })
        assert_equal 1, status.exitstatus
        document = JSON.parse(out)
        assert_nil document["data"]
        assert_equal "configuration_error", document.dig("error", "code")
        assert_includes err, key
        refute_includes out + err, PASSWORD
        refute_includes err, "canonical_cli.rb"
        assert_empty @server.requests
      end
    end
  end

  def test_canonical_invalid_invocations_fail_before_authentication
    invocations = [ ["describe"], ["describe", "card"], ["describe", "project", PARENT],
      ["describe", "cards", PARENT, "extra"], ["describe", "card", "not-a-card"], ["describe", "card", "http://[bad]/cards/123"],
      ["describe", "card", PARENT, "--unknown"], ["describe", "card", PARENT, "--output", "yaml"],
      ["describe", "dragon", "--help"], ["describe", "card", PARENT, "extra", "--help"],
      ["describe", "card", PARENT, "--output", "human"], ["create", "card"], ["unknown"] ]
    invocations.each do |args|
      out, err, status = planka("-o", "json", *args)
      assert_equal 2, status.exitstatus, args.inspect
      document = JSON.parse(out)
      assert_equal "invalid_input", document.dig("error", "code")
      assert_nil document["data"]
      refute_empty err
      refute_includes err, "canonical_cli.rb"
      assert_empty @server.requests
    end
  end

  def test_describe_accepts_same_instance_urls_and_common_flags_anywhere
    url = "#{@server.base_url}/cards/#{PARENT}/"
    [ ["-o", "json", "describe", "card", url],
      ["describe", "--output", "json", "cards", PARENT],
      ["describe", "card", "-o", "json", PARENT] ].each do |args|
      out, err, status = planka(*args)
      assert status.success?, err
      assert_empty err
      assert_equal PARENT, JSON.parse(out).dig("data", "id")
    end
    @server.requests.clear
    out, err, status = planka("describe", "card", "https://other.example/cards/#{PARENT}", "-o", "json")
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_includes err, "PLANKA_BASE_URL"
    assert_empty @server.requests
  end

  def test_describe_reports_sanitized_api_errors_and_cleans_up_sessions
    [ [401, "POST", %r{access-tokens$}, "authentication_error"],
      [403, "GET", %r{cards/#{PARENT}$}, "authorization_error"],
      [404, "GET", %r{cards/#{PARENT}$}, "not_found"],
      [500, "GET", %r{cards/#{PARENT}/comments$}, "api_error"] ].each do |code, method, path, expected|
      @server.requests.clear
      @server.inject(method, path, code, times: code >= 500 ? 3 : 1)
      out, err, status = planka("describe", "card", PARENT, "-o", "json")
      assert_equal 1, status.exitstatus
      document = JSON.parse(out)
      assert_equal expected, document.dig("error", "code")
      assert_nil document["data"]
      assert_equal({}, document["meta"])
      refute_includes out + err, "private upstream body"
      refute_includes out + err, PASSWORD
      refute_includes err, "canonical_cli.rb"
      if method == "GET"
        assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
      end
    end
  end

  def test_describe_cleanup_failure_does_not_mask_read_success
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("describe", "card", PARENT, "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal PARENT, JSON.parse(out).dig("data", "id")
    assert_includes err, "session cleanup failed"
    refute_includes out + err, "private upstream body"
  end

  def test_json_invocation_errors_preserve_output_selection_after_bad_flags
    out, err, status = planka("describe", "card", PARENT, "--unknown", "-o", "json")
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_includes err, "help"
    assert_empty @server.requests
  end

  def test_describe_network_failure_retains_primary_error_when_cleanup_also_fails
    # Net::HTTP retries a GET internally before the client retry loop.
    @server.inject("GET", %r{cards/#{PARENT}$}, :drop, times: 6)
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("describe", "card", PARENT, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "network_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    assert_includes err, "session cleanup failed"
    refute_includes out + err, "private upstream body"
    refute_includes err, "canonical_cli.rb"
  end

  def test_describe_accepts_card_urls_with_the_configured_instance_path
    base = "#{@server.base_url}/planka/"
    out, err, status = planka("describe", "card", "#{base}cards/#{PARENT}", "-o", "json",
      env: { "PLANKA_BASE_URL" => base })
    assert status.success?, err
    assert_equal "#{base}cards/#{PARENT}", JSON.parse(out).dig("data", "url")
  end

  def test_describe_malformed_api_payloads_emit_sanitized_failure_json
    [:malformed_card, :malformed_included].each do |fault|
      @server.inject("GET", %r{cards/#{PARENT}$}, fault)
      out, err, status = planka("describe", "card", PARENT, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal "api_error", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes err, "NoMethodError"
      refute_includes err, "TypeError"
      refute_includes err, "canonical_cli.rb"
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
  end

  def test_describe_tls_failures_obey_failure_and_cleanup_contracts
    [0, 4].each do |failure_after|
      @server.stop
      @server = FakePlanka.new(tls_failure_after: failure_after)
      cert_path = file("trusted-test.pem", @server.trusted_certificate)
      out, err, status = planka("describe", "card", PARENT, "-o", "json",
        env: { "SSL_CERT_FILE" => cert_path, "SSL_CERT_DIR" => File.dirname(cert_path) })
      document = JSON.parse(out)
      if failure_after.zero?
        assert_equal 1, status.exitstatus
        assert_equal "network_error", document.dig("error", "code")
        assert_nil document["data"]
      else
        assert status.success?, err
        assert_equal PARENT, document.dig("data", "id")
        assert_nil document["error"]
        assert_includes err, "session cleanup failed"
      end
      refute_includes err, "SSL_connect"
      refute_includes err, "canonical_cli.rb"
    end
  end

  def test_describe_rejects_malformed_descriptions_in_both_output_modes
    %w[human json].each do |output|
      @server.inject("GET", %r{cards/#{PARENT}$}, :malformed_description)
      out, err, status = planka("describe", "card", PARENT, "-o", output)
      assert_equal 1, status.exitstatus
      if output == "json"
        assert_equal "api_error", JSON.parse(out).dig("error", "code")
        assert_nil JSON.parse(out)["data"]
      else
        assert_empty out
      end
      assert_includes err, "Could not read complete resource details"
      refute_includes err, "NoMethodError"
      refute_includes err, ".rb:"
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
  end

  def test_describe_malformed_auth_response_obeys_canonical_failure_contract
    @server.inject("POST", %r{access-tokens$}, :malformed_auth)
    out, err, status = planka("describe", "card", PARENT, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes err, "TypeError"
    refute_includes err, "canonical_cli.rb"
    assert_equal [["POST", "/api/access-tokens"]], @server.requests.map { |m, p, _| [m, p] }
  end

  def test_canonical_commands_reject_invalid_session_tokens_before_resource_reads
    @server.inject("POST", %r{access-tokens$}, :invalid_token)
    out, err, status = planka("describe", "card", PARENT, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes out + err, "private upstream body"
    assert_equal [["POST", "/api/access-tokens"]], @server.requests.map { |m, p, _| [m, p] }
  end

  def test_card_related_board_payload_failures_are_reported_as_invalid_responses
    @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, :missing_board_records)
    out, err, status = planka("describe", "card", PARENT, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes err, "KeyError"
    refute_includes err, "cards/detail.rb"
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_snapshot_optional_collections_keep_their_legacy_and_canonical_shapes
    expected = { "boardId" => FakePlanka::BOARD_ID, "lists" => [], "cards" => [], "labels" => [],
      "cardLabels" => [], "taskLists" => [], "tasks" => [], "cardMemberships" => [] }
    @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, :missing_board_records)
    assert_equal expected, ok_json("snapshot", "--board", FakePlanka::BOARD_ID)
    @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, :missing_board_records)
    out, err, status = planka("describe", "board", FakePlanka::BOARD_ID, "-o", "json")
    assert status.success?, err
    assert_empty err
    assert_equal({ "data" => expected, "meta" => {}, "error" => nil }, JSON.parse(out))
  end

  def test_publishes_reads_back_and_preserves_the_whole_workflow
    criteria = [ %(Handles "quoted" punctuation, commas.), "Supports\nmultiline and ünïcode 多行" ]

    # 1. Read the board and the parent spec with its comment.
    parent = ok_json("show", PARENT)
    assert_equal "Original description.", parent["description"]
    assert_equal "ready-for-agent", parent["listName"]
    assert_equal [ "Parent context note." ], parent["comments"].map { |c| c["text"] }
    assert_empty parent["taskLists"], "a spec has no acceptance criteria"

    # 2. Create a feature label (reusing enhancement) and attach both to the parent.
    feature = ok_json("create-label", "--name", "feature:work-next")
    assert feature["created"]
    feature_id = feature["label"]["id"]
    refute ok_json("create-label", "--name", "enhancement")["created"], "enhancement is reused by name"
    assert ok_json("apply-label", PARENT, "--label", "enhancement")["created"]
    assert ok_json("apply-label", PARENT, "--label", "feature:work-next")["created"]

    # 3. Create a spec: a project card with no acceptance criteria.
    spec = ok_json("create-spec", "--list", "ready-for-agent", "--title", "Spec: Sub-feature",
      "--description-file", file("spec.md", "Spec body.\nSecond line."))
    spec_id = spec["card"]["id"]
    assert_equal "#{@server.base_url}/cards/#{spec_id}", spec["card"]["url"]

    # 4. Create two tickets, each with one correctly named Acceptance criteria list.
    t1 = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Ticket one",
      "--criteria-file", file("c1.json", JSON.generate(criteria)))
    t2 = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Ticket two",
      "--criteria-file", file("c2.json", JSON.generate(criteria)))
    [ t1, t2 ].each do |ticket|
      assert_equal "Acceptance criteria", ticket["taskList"]["name"]
      assert_equal criteria, ticket["tasks"].map { |t| t["name"] }
      assert ticket["completed"]
    end
    t1_id = t1["card"]["id"]
    t2_id = t2["card"]["id"]
    [ t1_id, t2_id ].each do |id|
      ok("apply-label", id, "--label", "enhancement")
      ok("apply-label", id, "--label", "feature:work-next")
    end

    # 5. Link the second ticket to the first; repeating link and apply is safe.
    assert_includes ok("link", t2_id, t1_id), "linked: #{t1_id}"
    assert_includes ok("link", t2_id, t1_id), "already linked: #{t1_id}"
    refute ok_json("apply-label", t2_id, "--label", "enhancement")["created"], "re-apply is idempotent"

    # 6. Move the parent spec to in-progress without claiming it.
    ok("move-card", PARENT, "--list", "in-progress")
    assert_empty @server.memberships, "moving a spec adds no membership"
    assert_equal "in-progress", ok_json("show", PARENT)["listName"]

    # 7. Update the parent description from a multiline file.
    body = "Rewritten spec.\n\n- includes Python requirement\n- \"quoted\" and 多行"
    ok("update-card", PARENT, "--description-file", file("desc.md", body))
    assert_equal body, ok_json("show", PARENT)["description"]

    # 8. Read everything back and verify content, labels, criteria and blockers.
    spec_detail = ok_json("show", spec_id)
    assert_empty spec_detail["taskLists"], "the spec stayed a spec"

    t1_detail = ok_json("show", t1_id)
    assert_equal 1, t1_detail["taskLists"].size, "exactly one list, no leftover Tasks"
    assert_equal criteria, t1_detail["taskLists"].first["tasks"].map { |t| t["name"] }
    assert_equal %w[enhancement feature:work-next].sort, t1_detail["labels"].map { |l| l["name"] }.sort

    t2_detail = ok_json("show", t2_id)
    assert_equal [ t1_id ], t2_detail["blockers"].map { |b| b["cardId"] }
    refute t2_detail["blockers"].first["completed"]

    assert_includes ok_json("snapshot")["cards"].map { |c| c["id"] }, spec_id

    # The picker's invariants still hold for the created cards.
    with_client do |client|
      board = Planka::Workflow::Board.new(Planka::Board.new(client.board(@server.board_id), base_url: @server.base_url))
      refute board.card(spec_id).ticket?, "spec is not a ticket"
      assert board.card(t1_id).ticket?, "ticket has acceptance criteria"
      assert board.card(t1_id).takeable?, "ticket one is takeable"
      refute board.card(t2_id).takeable?, "ticket two is blocked by ticket one"
      assert_equal [ t1_id ], board.card(t2_id).open_blockers.map(&:id)
      assert board.card(PARENT).labelled?("feature:work-next")
      assert feature_id
    end
  end

  def test_create_and_rename_task_list_preserves_its_tasks
    created = ok_json("create-task-list", PARENT, "--name", "Tasks")
    assert created["created"]
    list_id = created["taskList"]["id"]
    with_client { |client| client.create_task(list_id, name: "keep me", position: 1000) }

    renamed = ok_json("rename-task-list", "--id", list_id, "--name", "Acceptance criteria")
    assert_equal "Acceptance criteria", renamed["taskList"]["name"]

    list = ok_json("show", PARENT)["taskLists"].find { |l| l["id"] == list_id }
    assert_equal "Acceptance criteria", list["name"]
    assert_equal [ "keep me" ], list["tasks"].map { |t| t["name"] }, "the task survived the rename"
  end

  def test_labels_and_single_list_snapshot_are_read_only_views
    assert_includes ok_json("labels")["labels"].map { |l| l["name"] }, "enhancement"

    listing = ok_json("snapshot", "--list", "ready-for-agent")
    assert_equal FakePlanka::LIST_READY, listing["listId"]
    assert_equal [ PARENT ], listing["cards"].map { |c| c["id"] }
  end

  def test_show_is_human_readable_by_default_and_json_when_requested
    out = ok("show", PARENT)
    assert_includes out, "Spec: Work-next refinement"
    assert_includes out, "List: ready-for-agent"
    assert_includes out, "Original description."
    assert_includes out, "Comments:"
    assert_includes out, "Parent context note."
    refute out.start_with?("{")

    doc = JSON.parse(ok("show", PARENT, "--output", "json"))
    assert_equal PARENT, doc["id"]
    assert_equal "Spec: Work-next refinement", doc["name"]
  end

  def test_snapshot_is_human_readable_by_default_and_json_when_requested
    out = ok("snapshot")
    assert_includes out, "Board #{FakePlanka::BOARD_ID}"
    assert_includes out, "ready-for-agent"
    assert_includes out, "Spec: Work-next refinement"
    refute out.start_with?("{")

    doc = JSON.parse(ok("snapshot", "--output", "json"))
    assert_equal FakePlanka::BOARD_ID, doc["boardId"]
    assert_equal [ PARENT ], doc["cards"].map { |card| card["id"] }
  end

  def test_labels_are_human_readable_by_default_and_json_when_requested
    out = ok("labels")
    assert_includes out, "enhancement"
    assert_includes out, "berry-red"
    refute out.start_with?("{")

    doc = JSON.parse(ok("labels", "--output", "json"))
    assert_equal [ "enhancement" ], doc["labels"].map { |label| label["name"] }
  end

  def test_create_list_reports_human_success_and_json_when_requested
    out = ok("create-list", "--name", "triage")
    assert_includes out, "Created list: triage"
    refute out.start_with?("{")

    doc = JSON.parse(ok("create-list", "--name", "backlog", "--output", "json"))
    assert_equal "backlog", doc.dig("list", "name")
    assert doc["created"]
  end

  def test_create_spec_reports_human_success_and_json_when_requested
    out = ok("create-spec", "--list", "ready-for-agent", "--title", "Human spec")
    assert_includes out, "Created card: Human spec"
    assert_includes out, @server.base_url
    refute out.start_with?("{")

    doc = JSON.parse(ok("create-spec", "--list", "ready-for-agent", "--title", "Agent spec", "--output", "json"))
    assert_equal "Agent spec", doc.dig("card", "name")
  end

  def test_create_ticket_reports_human_success_and_json_when_requested
    criteria = file("human-ticket.json", JSON.generate([ "Works" ]))
    out = ok("create-ticket", "--list", "ready-for-agent", "--title", "Human ticket", "--criteria-file", criteria)
    assert_includes out, "Created ticket: Human ticket"
    assert_includes out, "Acceptance criteria: 1"
    refute out.start_with?("{")

    doc = JSON.parse(ok("create-ticket", "--list", "ready-for-agent", "--title", "Agent ticket",
      "--criteria-file", criteria, "--output", "json"))
    assert doc["completed"]
    assert_equal "Agent ticket", doc.dig("card", "name")
  end

  def test_update_card_reports_human_success_and_json_when_requested
    out = ok("update-card", PARENT, "--title", "Human title")
    assert_includes out, "Updated card: Human title"
    refute out.start_with?("{")

    doc = JSON.parse(ok("update-card", PARENT, "--title", "Agent title", "--output", "json"))
    assert_equal "Agent title", doc.dig("card", "name")
  end

  def test_move_card_reports_human_success_and_json_when_requested
    out = ok("move-card", PARENT, "--list", "in-progress")
    assert_includes out, "Moved card: Spec: Work-next refinement"
    refute out.start_with?("{")

    doc = JSON.parse(ok("move-card", PARENT, "--list", "done", "--output", "json"))
    assert_equal FakePlanka::LIST_DONE, doc.dig("card", "listId")
  end

  def test_create_label_reports_created_or_reused_for_humans_and_json_when_requested
    out = ok("create-label", "--name", "feature:human")
    assert_includes out, "Created label: feature:human"
    reused = ok("create-label", "--name", "enhancement")
    assert_includes reused, "Reused label: enhancement"

    doc = JSON.parse(ok("create-label", "--name", "feature:agent", "--output", "json"))
    assert doc["created"]
    assert_equal "feature:agent", doc.dig("label", "name")
  end

  def test_apply_label_reports_applied_or_present_for_humans_and_json_when_requested
    out = ok("apply-label", PARENT, "--label", "enhancement")
    assert_includes out, "Applied label #{FakePlanka::LABEL_ENHANCEMENT} to card #{PARENT}"
    present = ok("apply-label", PARENT, "--label", "enhancement")
    assert_includes present, "already has label"

    doc = JSON.parse(ok("apply-label", PARENT, "--label", "enhancement", "--output", "json"))
    refute doc["created"]
    assert_equal PARENT, doc["cardId"]
  end

  def test_create_task_list_reports_human_success_and_json_when_requested
    out = ok("create-task-list", PARENT, "--name", "Human tasks")
    assert_includes out, "Created task list: Human tasks"
    refute out.start_with?("{")

    doc = JSON.parse(ok("create-task-list", PARENT, "--name", "Agent tasks", "--output", "json"))
    assert_equal "Agent tasks", doc.dig("taskList", "name")
  end

  def test_rename_task_list_reports_human_success_and_json_when_requested
    created = JSON.parse(ok("create-task-list", PARENT, "--name", "Before", "--output", "json"))
    id = created.dig("taskList", "id")

    out = ok("rename-task-list", "--id", id, "--name", "Human name")
    assert_includes out, "Renamed task list: Human name"
    refute out.start_with?("{")

    doc = JSON.parse(ok("rename-task-list", "--id", id, "--name", "Agent name", "--output", "json"))
    assert_equal "Agent name", doc.dig("taskList", "name")
  end

  def test_branch_name_keeps_human_text_and_offers_json
    assert_equal "card/spec-work-next-refinement\n", ok("branch-name", PARENT)

    doc = JSON.parse(ok("branch-name", PARENT, "--output", "json"))
    assert_equal "card/spec-work-next-refinement", doc["branch"]
    assert_equal PARENT, doc["cardId"]
  end

  def test_workflow_branch_name_preserves_legacy_naming_and_has_no_resource_writes
    start = @server.requests.length
    out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json")
    assert status.success?, err
    assert_empty err
    expected = { "cardId" => PARENT, "branch" => "card/spec-work-next-refinement" }
    assert_equal({ "data" => expected, "meta" => {}, "error" => nil }, JSON.parse(out))
    assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/cards/#{PARENT}"],
      ["GET", "/api/boards/#{FakePlanka::BOARD_ID}"], ["DELETE", "/api/access-tokens/me"]],
      @server.requests.drop(start).map { |method, path, _| [method, path] }
    assert_equal expected, ok_json("branch-name", PARENT)
    direct, direct_err, direct_status = planka_executable("branch-name", PARENT, "--output", "json")
    assert direct_status.success?, direct_err
    assert_equal expected, JSON.parse(direct)
    assert_equal "card/spec-work-next-refinement\n", ok("workflow", "branch-name", PARENT)
  end

  def test_workflow_branch_name_rejects_an_unusable_prefix_before_network
    out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json",
      env: { "PLANKA_BRANCH_PREFIX" => "x" * 56 })
    assert_equal 1, status.exitstatus
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    assert_includes err, "PLANKA_BRANCH_PREFIX"
    refute_includes err, "x" * 56
    assert_empty @server.requests
  end

  def test_workflow_branch_name_rejects_malformed_naming_records_in_both_formats
    [:malformed_branch_title, :malformed_feature_label, :missing_feature_label].each do |fault|
      %w[human json].each do |output|
        @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, fault)
        out, err, status = planka("workflow", "branch-name", PARENT, "-o", output)
        assert_equal 1, status.exitstatus
        if output == "json"
          assert_equal "api_error", JSON.parse(out).dig("error", "code")
          assert_nil JSON.parse(out)["data"]
        else
          assert_empty out
        end
        assert_includes err, "Could not read complete resource details"
        refute_includes err, ".rb:"
        assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
      end
    end
  end

  def test_workflow_branch_name_uses_the_first_feature_and_reserves_prefix_space
    @server.find_card(PARENT)["name"] = "1.2 An account signs in; the first admin exists"
    @server.add_label("feature:tracer")
    first = @server.labels.last["id"]
    @server.add_label("feature:other")
    second = @server.labels.last["id"]
    @server.card_labels << { "cardId" => PARENT, "labelId" => first }
    @server.card_labels << { "cardId" => PARENT, "labelId" => second }
    env = { "PLANKA_BRANCH_PREFIX" => "lucenta-" }
    expected = { "cardId" => PARENT, "branch" => "feature/tracer-1.2-an-account-signs-in-the-first-admin" }
    out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json", env: env)
    assert status.success?, err
    assert_equal expected, JSON.parse(out)["data"]
    assert_equal expected, JSON.parse(ok("branch-name", PARENT, "-o", "json", env: env))
    assert_equal "#{expected['branch']}\n", ok("workflow", "branch-name", PARENT, env: env)
  end

  def test_workflow_branch_name_keeps_prefix_boundaries_and_other_reads_independent
    { 40 => "card/spec-work-next", 55 => "card/spe" }.each do |length, branch|
      env = { "PLANKA_BRANCH_PREFIX" => "x" * length }
      out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json", env: env)
      assert status.success?, err
      assert_equal branch, JSON.parse(out).dig("data", "branch")
      assert_equal branch, JSON.parse(ok("branch-name", PARENT, "-o", "json", env: env))["branch"]
    end
    out, err, status = planka("describe", "card", PARENT, "-o", "json",
      env: { "PLANKA_BRANCH_PREFIX" => "x" * 56 })
    assert status.success?, err
    assert_equal PARENT, JSON.parse(out).dig("data", "id")
  end

  def test_workflow_branch_name_validates_input_and_settings_before_network
    [ [[], {}, "invalid_input", 2],
      [[PARENT, "extra"], {}, "invalid_input", 2],
      [[PARENT, "--limit", "1"], {}, "invalid_input", 2],
      [[PARENT, "--output", "human"], {}, "invalid_input", 2],
      [["https://other.example/cards/#{PARENT}"], {}, "invalid_input", 2],
      [[PARENT], { "PLANKA_AGENT_PASSWORD" => nil }, "configuration_error", 1] ].each do |args, env, code, exit_status|
      out, err, status = planka("-o", "json", "workflow", "branch-name", *args, env: env)
      assert_equal exit_status, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes err, PASSWORD
    end
    assert_empty @server.requests
  end

  def test_workflow_branch_name_accepts_instance_urls_and_output_flag_positions
    base = "#{@server.base_url}/planka/"
    url = "#{base}cards/#{PARENT}/"
    [["-o", "json", "workflow", "branch-name", url],
      ["workflow", "-ojson", "branch-name", url],
      ["workflow", "branch-name", url, "--output=json"]].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_BASE_URL" => base, "PLANKA_BOARD_ID" => "999999", "PLANKA_BRANCH_PREFIX" => nil })
      assert status.success?, err
      assert_empty err
      assert_equal PARENT, JSON.parse(out).dig("data", "cardId")
      assert_equal "card/spec-work-next-refinement", JSON.parse(out).dig("data", "branch")
    end
  end

  def test_workflow_branch_name_reports_api_failures_and_preserves_reads_after_cleanup_failure
    { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found",
      :malformed_card => "api_error", :malformed_board_reference => "api_error",
      :malformed_board_path => "api_error" }.each do |fault, code|
      @server.inject("GET", %r{cards/#{PARENT}$}, fault)
      start = @server.requests.length
      out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "private upstream body"
      assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/cards/#{PARENT}"],
        ["DELETE", "/api/access-tokens/me"]], @server.requests.drop(start).map { |method, path, _| [method, path] }
    end
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "branch-name", PARENT, "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal "card/spec-work-next-refinement", JSON.parse(out).dig("data", "branch")
    assert_includes err, "planka workflow branch-name: session cleanup failed"
  end

  def test_unticked_keeps_one_criterion_per_line_and_offers_json
    criteria = [ "First criterion", "Second criterion" ]
    ticket = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Criteria ticket",
      "--criteria-file", file("unticked.json", JSON.generate(criteria)))
    id = ticket.dig("card", "id")

    assert_equal "First criterion\nSecond criterion\n", ok("unticked", id)
    doc = JSON.parse(ok("unticked", id, "--output", "json"))
    assert_equal id, doc["cardId"]
    assert_equal criteria, doc["criteria"]
  end

  def test_pending_criteria_preserves_workflow_rules_and_legacy_output_without_writes
    ticket = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Criteria ticket",
      "--criteria-file", file("pending.json", JSON.generate(["Done criterion", "Second pending", "First pending"])))
    id = ticket.dig("card", "id")
    @server.tasks.first["isCompleted"] = true
    @server.tasks.last["position"] = 1
    @server.task_lists << { "id" => "999", "cardId" => id, "name" => "Other tasks" }
    @server.tasks << { "id" => "998", "taskListId" => "999", "name" => "Not acceptance criteria", "isCompleted" => false }
    start = @server.requests.length
    out, err, status = planka("workflow", "pending-criteria", id, "-o", "json")
    assert status.success?, err
    assert_empty err
    expected = { "cardId" => id, "criteria" => ["Second pending", "First pending"] }
    assert_equal({ "data" => expected, "meta" => {}, "error" => nil }, JSON.parse(out))
    assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/cards/#{id}"],
      ["GET", "/api/boards/#{FakePlanka::BOARD_ID}"], ["DELETE", "/api/access-tokens/me"]],
      @server.requests.drop(start).map { |method, path, _| [method, path] }
    assert_equal expected, ok_json("unticked", id)
    direct, direct_err, direct_status = planka_executable("unticked", id, "--output", "json")
    assert direct_status.success?, direct_err
    assert_equal expected, JSON.parse(direct)
    assert_equal "Second pending\nFirst pending\n", ok("workflow", "pending-criteria", id)
    assert_equal ok("unticked", id), ok("workflow", "pending-criteria", id)
  end

  def test_pending_criteria_rejects_malformed_task_records_in_both_output_modes
    %w[human json].each do |output|
      @server.inject("GET", %r{boards/#{FakePlanka::BOARD_ID}$}, :malformed_criteria)
      out, err, status = planka("workflow", "pending-criteria", PARENT, "-o", output)
      assert_equal 1, status.exitstatus
      if output == "json"
        assert_equal "api_error", JSON.parse(out).dig("error", "code")
        assert_nil JSON.parse(out)["data"]
      else
        assert_empty out
      end
      assert_match(/\Aplanka workflow pending-criteria: Could not read complete resource details/, err)
      refute_includes err, ".rb:"
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
  end

  def test_pending_criteria_rejects_malformed_board_references_before_board_reads
    [:malformed_board_reference, :malformed_board_path].each do |fault|
      @server.inject("GET", %r{cards/#{PARENT}$}, fault)
      start = @server.requests.length
      out, err, status = planka("workflow", "pending-criteria", PARENT, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal "api_error", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "not-an-id"
      refute_includes out + err, "../cards/123"
      assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/cards/#{PARENT}"],
        ["DELETE", "/api/access-tokens/me"]], @server.requests.drop(start).map { |method, path, _| [method, path] }
    end
  end

  def test_pending_criteria_empty_results_are_successful_with_or_without_a_criteria_list
    assert_equal({ "data" => { "cardId" => PARENT, "criteria" => [] }, "meta" => {}, "error" => nil },
      JSON.parse(ok("workflow", "pending-criteria", PARENT, "-o", "json")))
    assert_equal "\n", ok("workflow", "pending-criteria", PARENT)
    ticket = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Completed ticket",
      "--criteria-file", file("done.json", '["Done"]'))
    @server.tasks.first["isCompleted"] = true
    id = ticket.dig("card", "id")
    assert_equal [], JSON.parse(ok("workflow", "pending-criteria", id, "-o", "json")).dig("data", "criteria")
    assert_equal ok("unticked", id), ok("workflow", "pending-criteria", id)
  end

  def test_pending_criteria_validates_input_and_configuration_before_network
    [ [[], {}, "invalid_input", 2],
      [[PARENT, "extra"], {}, "invalid_input", 2],
      [[PARENT, "--limit", "1"], {}, "invalid_input", 2],
      [[PARENT, "--output", "human"], {}, "invalid_input", 2],
      [["https://other.example/cards/#{PARENT}"], {}, "invalid_input", 2],
      [[PARENT], { "PLANKA_AGENT_PASSWORD" => nil }, "configuration_error", 1] ].each do |args, env, code, exit_status|
      out, err, status = planka("-o", "json", "workflow", "pending-criteria", *args, env: env)
      assert_equal exit_status, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes err, PASSWORD
    end
    assert_empty @server.requests
  end

  def test_pending_criteria_accepts_instance_path_urls_and_common_output_flag_positions
    base = "#{@server.base_url}/planka/"
    url = "#{base}cards/#{PARENT}/"
    [["-o", "json", "workflow", "pending-criteria", url],
      ["workflow", "-ojson", "pending-criteria", url],
      ["workflow", "pending-criteria", url, "--output=json"]].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_BASE_URL" => base, "PLANKA_BOARD_ID" => "999999" })
      assert status.success?, err
      assert_empty err
      assert_equal PARENT, JSON.parse(out).dig("data", "cardId")
    end
  end

  def test_pending_criteria_api_failures_and_cleanup_obey_canonical_contract
    { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found",
      :malformed_card => "api_error" }.each do |fault, code|
      @server.inject("GET", %r{cards/#{PARENT}$}, fault)
      out, err, status = planka("workflow", "pending-criteria", PARENT, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "private upstream body"
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "pending-criteria", PARENT, "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal [], JSON.parse(out).dig("data", "criteria")
    assert_includes err, "planka workflow pending-criteria: session cleanup failed"
  end

  def test_comment_confirms_human_success_and_returns_created_comment_as_json
    out = ok("comment", PARENT, "Human note")
    assert_includes out, "Commented on card #{PARENT}"

    doc = JSON.parse(ok("comment", PARENT, "Agent note", "--output", "json"))
    assert_equal PARENT, doc["cardId"]
    assert_equal "Agent note", doc.dig("comment", "text")
    assert doc.dig("comment", "id")
  end

  def test_claim_keeps_human_confirmation_and_offers_json
    out = ok("claim", PARENT)
    assert_includes out, "claimed: Spec: Work-next refinement"

    doc = JSON.parse(ok("claim", PARENT, "--output", "json"))
    assert_equal PARENT, doc.dig("card", "id")
    assert_equal FakePlanka::LIST_PROGRESS, doc.dig("card", "listId")
    assert doc["claimed"]
    refute doc["memberAdded"], "re-claim reports that membership already existed"
  end

  def test_link_keeps_human_lines_and_offers_structured_json
    blocker = ok_json("create-spec", "--list", "ready-for-agent", "--title", "Blocker").dig("card", "id")
    assert_includes ok("link", PARENT, blocker), "linked: #{blocker} (open)"

    doc = JSON.parse(ok("link", PARENT, blocker, "--output", "json"))
    assert_equal PARENT, doc["blockedCardId"]
    assert_equal blocker, doc.dig("links", 0, "blockerCardId")
    assert_equal "already-linked", doc.dig("links", 0, "status")
  end

  def test_next_card_keeps_human_report_and_offers_structured_json
    ticket = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "Next ticket",
      "--criteria-file", file("next.json", JSON.generate([ "Works" ])))
    id = ticket.dig("card", "id")

    assert_includes ok("next-card"), "card: Next ticket"
    doc = JSON.parse(ok("next-card", "--output", "json"))
    assert_equal id, doc.dig("card", "id")
    assert_equal "main", doc["parent"]
    assert_empty doc["blockers"]
  end

  def test_loop_lock_keeps_human_status_and_offers_structured_json
    assert_equal "free\n", ok("loop-lock")
    ok("claim", PARENT)

    assert_includes ok("loop-lock"), "held: Spec: Work-next refinement"
    doc = JSON.parse(ok("loop-lock", "--output", "json"))
    assert doc["held"]
    assert_equal PARENT, doc.dig("card", "id")
    assert_kind_of Integer, doc["ageSeconds"]
  end

  def test_workflow_claim_status_reports_free_without_a_target_or_resource_writes
    out, err, status = planka("workflow", "claim-status", "-o", "json",
      env: { "PLANKA_BOARD_ID" => nil, "PLANKA_BRANCH_PREFIX" => "x" * 56 })
    assert status.success?, err
    assert_empty err
    assert_equal({ "data" => { "held" => false, "card" => nil }, "meta" => {}, "error" => nil }, JSON.parse(out))
    assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/projects"],
      ["GET", "/api/boards/#{@server.board_id}"], ["GET", "/api/users/me"],
      ["DELETE", "/api/access-tokens/me"]], @server.requests.map { |method, path, _| [method, path] }
    assert_equal "free\n", ok("workflow", "claim-status")
    assert_equal "free\n", ok("loop-lock")
  end

  def test_workflow_claim_status_rejects_malformed_board_discovery_before_board_reads
    @server.inject("GET", %r{/api/projects\z}, :malformed_projects)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    refute_match(/NoMethodError|private|undefined method/, err)
    assert_equal 0, @server.counts("GET", %r{/api/boards/})
    assert_equal 1, @server.counts("DELETE", %r{/api/access-tokens/me\z})
  end

  def test_workflow_claim_status_sanitizes_an_invalid_claim_timestamp_in_both_formats
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "private-invalid-date" }
    %w[human json].each do |format|
      out, err, status = planka("workflow", "claim-status", "-o", format)
      assert_equal 1, status.exitstatus
      refute_match(/ArgumentError|private-invalid|backtrace|xmlschema/, err)
      if format == "json"
        assert_equal "api_error", JSON.parse(out).dig("error", "code")
        assert_nil JSON.parse(out)["data"]
      else
        assert_empty out
      end
    end
    assert_equal 2, @server.counts("DELETE", %r{/api/access-tokens/me\z})
  end

  def test_workflow_claim_status_rejects_a_malformed_signed_in_identity
    @server.inject("GET", %r{/api/users/me\z}, :malformed_user)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    refute_match(/NoMethodError|undefined method/, err)
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    assert_equal 1, @server.counts("DELETE", %r{/api/access-tokens/me\z})
  end

  def test_workflow_claim_status_sanitizes_malformed_handoff_comments
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    @server.inject("GET", %r{/api/cards/#{PARENT}/comments\z}, :malformed_comments, times: 2)
    %w[human json].each do |format|
      out, err, status = planka("workflow", "claim-status", "-o", format)
      assert_equal 1, status.exitstatus
      refute_match(/TypeError|NoMethodError|private/, err)
      if format == "json"
        assert_equal "api_error", JSON.parse(out).dig("error", "code")
        assert_nil JSON.parse(out)["data"]
      else
        assert_empty out
      end
    end
  end

  def test_workflow_claim_status_rejects_a_malformed_card_name
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    @server.inject("GET", %r{/api/boards/.+\z}, :malformed_branch_title)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_match(/TypeError|NoMethodError|private/, err)
  end

  def test_workflow_claim_status_does_not_report_free_for_invalid_membership_or_list_records
    membership = { "cardId" => PARENT, "userId" => 42, "createdAt" => "2026-10-01T00:00:00Z" }
    @server.memberships << membership
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    membership["userId"] = "user-bot"
    @server.find_card(PARENT)["listId"] = "999"
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    refute_match(/TypeError|NoMethodError/, err)
  end

  def test_quarantined_claims_are_free_for_claim_status_but_held_for_legacy_loop_lock
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    @server.labels << { "id" => "300000000000000099", "name" => "quarantine", "boardId" => FakePlanka::BOARD_ID }
    @server.card_labels << { "cardId" => PARENT, "labelId" => "300000000000000099" }
    assert_equal({ "held" => false, "card" => nil }, ok_json("workflow", "claim-status")["data"])
    assert_equal true, ok_json("loop-lock")["held"]
  end

  def test_workflow_claim_status_preserves_held_and_latest_handoff_rules
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    data = ok_json("workflow", "claim-status")["data"]
    assert_equal true, data["held"]
    assert_equal({ "id" => PARENT, "name" => "Spec: Work-next refinement", "url" => "#{@server.base_url}/cards/#{PARENT}" }, data["card"])
    assert_equal "2026-10-01T00:00:00Z", data["claimedAt"]
    assert_kind_of Integer, data["ageSeconds"]
    human = ok("workflow", "claim-status")
    legacy = ok("loop-lock")
    assert_equal legacy.gsub(/^age: -?\d+$/, "age: seconds"), human.gsub(/^age: -?\d+$/, "age: seconds")
    legacy_data = ok_json("loop-lock")
    assert_equal data.reject { |key, _| key == "ageSeconds" }, legacy_data.reject { |key, _| key == "ageSeconds" }
    @server.comments << { "cardId" => PARENT, "text" => "Branch: topic\nPR: https://github.com/example/repo/pull/1", "createdAt" => "2026-10-02T00:00:00Z" }
    assert_equal({ "held" => false, "card" => nil }, ok_json("workflow", "claim-status")["data"])
    @server.comments << { "cardId" => PARENT, "text" => "Branch: newer-topic", "createdAt" => "2026-10-03T00:00:00Z" }
    assert_equal true, ok_json("workflow", "claim-status").dig("data", "held")
    @server.find_card(PARENT)["listId"] = FakePlanka::LIST_DONE
    assert_equal false, ok_json("workflow", "claim-status").dig("data", "held")
    assert_equal 0, @server.counts("GET", %r{/api/cards/[^/]+\z})
    assert @server.requests.all? { |method, path, _| method == "GET" || path.start_with?("/api/access-tokens") }
  end

  def test_workflow_claim_status_reads_other_boards_despite_a_configured_board
    board_id, list_id, card_id = "100000000000000002", "200000000000000004", "400000000000000002"
    @server.boards << { "id" => board_id }
    @server.lists << { "id" => list_id, "name" => "Any active list", "type" => "active", "boardId" => board_id }
    @server.cards << @server.find_card(PARENT).merge("id" => card_id, "boardId" => board_id, "listId" => list_id, "name" => "Other board claim")
    @server.memberships << { "cardId" => PARENT, "userId" => "someone-else", "createdAt" => "2026-10-01T00:00:00Z" }
    @server.memberships << { "cardId" => card_id, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    data = ok_json("workflow", "claim-status")["data"]
    assert_equal card_id, data.dig("card", "id")
    assert_equal ["/api/boards/#{@server.board_id}", "/api/boards/#{board_id}"], @server.requests.filter_map { |method, path, _| path if method == "GET" && path.start_with?("/api/boards/") }
    assert_equal 0, @server.counts("GET", %r{/api/cards/#{PARENT}/comments\z})
    assert_equal 1, @server.counts("GET", %r{/api/cards/#{card_id}/comments\z})
  end

  def test_workflow_claim_status_validates_arguments_and_configuration_before_network
    cases = [
      [["workflow", "claim-status", PARENT], {}, 2, "invalid_input"],
      [["workflow", "claim-status", "--board", @server.board_id], {}, 2, "invalid_input"],
      [["workflow", "claim-status", "--limit", "1"], {}, 2, "invalid_input"],
      [["workflow", "claim-statuses"], {}, 2, "invalid_input"],
      [["workflow", "claim-status", "-o", "json", "-o", "human"], {}, 2, "invalid_input"],
      [["workflow", "claim-status"], { "PLANKA_AGENT_PASSWORD" => nil }, 1, "configuration_error"],
      [["workflow", "claim-status"], { "PLANKA_BASE_URL" => "https://private:password@planka.test" }, 1, "configuration_error"],
    ]
    cases.each do |args, env, expected_status, code|
      out, err, status = planka(*args, "-o", "json", env: env)
      assert_equal expected_status, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      refute_includes err, PASSWORD
    end
    assert_empty @server.requests
  end

  def test_workflow_claim_status_accepts_output_flag_positions_and_empty_board_scope
    @server.boards.clear
    [["-o", "json", "workflow", "claim-status"], ["workflow", "-o", "json", "claim-status"],
      ["workflow", "claim-status", "--output=json"]].each do |args|
      out, err, status = planka(*args)
      assert status.success?, err
      assert_empty err
      assert_equal({ "data" => { "held" => false, "card" => nil }, "meta" => {}, "error" => nil }, JSON.parse(out))
    end
    assert_equal 0, @server.counts("GET", %r{/api/boards/})
  end

  def test_workflow_claim_status_rejects_unsafe_board_ids_without_requesting_them
    @server.inject("GET", %r{/api/projects\z}, :unsafe_board_id)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_equal 0, @server.counts("GET", %r{/api/boards/})
    assert_equal 0, @server.counts("GET", %r{/api/users/me\z})
    refute_match(/\.\.\/|TypeError|NoMethodError/, err)
  end

  def test_workflow_claim_status_preserves_api_failures_and_success_after_cleanup_failure
    [[403, %r{/api/projects\z}, "authorization_error"], [404, %r{/api/boards/.+\z}, "not_found"],
      [401, %r{/api/users/me\z}, "authentication_error"]].each do |http_status, path, code|
      @server.inject("GET", path, http_status)
      out, err, status = planka("workflow", "claim-status", "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_match(/private upstream|TypeError|NoMethodError/, err)
    end
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 403)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert status.success?, err
    assert_equal({ "data" => { "held" => false, "card" => nil }, "meta" => {}, "error" => nil }, JSON.parse(out))
    assert_includes err, "cleanup failed"
    assert_equal 4, @server.counts("DELETE", %r{/api/access-tokens/me\z})
  end

  def test_workflow_claim_status_refuses_to_guess_between_duplicate_card_records
    @server.memberships << { "cardId" => PARENT, "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00Z" }
    @server.cards << @server.find_card(PARENT).merge("listId" => FakePlanka::LIST_DONE)
    out, err, status = planka("workflow", "claim-status", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_match(/TypeError|NoMethodError/, err)
  end

  def test_spec_sweep_reports_no_work_for_humans_and_json
    assert_equal "No finished specs\n", ok("spec-sweep")

    doc = JSON.parse(ok("spec-sweep", "--output", "json"))
    assert_equal 0, doc["count"]
    assert_empty doc["moved"]
  end

  def test_direct_command_executable_has_the_same_json_contract
    dispatched = JSON.parse(ok("show", PARENT, "--output", "json"))
    out, err, status = planka_executable("show", PARENT, "--output", "json")

    assert status.success?, err
    assert_equal dispatched, JSON.parse(out)
  end

  def test_unknown_write_outcome_is_human_readable_without_json_output
    @server.inject("POST", %r{/api/lists/.+/cards\z}, :apply_then_drop)
    out, err, status = planka("create-spec", "--list", "ready-for-agent", "--title", "Risky human spec")

    refute status.success?
    assert_includes out, "Outcome unknown"
    assert_includes out, "read the board back before retrying"
    refute out.start_with?("{")
    assert_includes err, "planka create-spec:"
  end

  def test_an_ambiguous_label_name_is_rejected_but_an_id_still_works
    @server.add_label("enhancement")
    _out, err, status = planka("apply-label", PARENT, "--label", "enhancement")
    refute status.success?
    assert_includes err, "ambiguous label name"

    by_id = ok_json("apply-label", PARENT, "--label", @server.labels.first["id"])
    assert by_id["created"], "applying a duplicate-named label by id still works"
  end

  def test_create_list_adds_a_column_cards_can_target
    created = ok_json("create-list", "--name", "triage")
    assert created["created"]
    assert_equal "active", created["list"]["type"]
    assert_includes ok_json("snapshot")["lists"].map { |l| l["name"] }, "triage"

    spec = ok_json("create-spec", "--list", "triage", "--title", "In triage")
    assert_equal "triage", ok_json("show", spec["card"]["id"])["listName"]
  end

  def test_create_spec_and_ticket_without_a_description
    spec = ok_json("create-spec", "--list", "ready-for-agent", "--title", "No-description spec")
    assert spec["card"]["id"], "a spec needs no description"

    ticket = ok_json("create-ticket", "--list", "ready-for-agent", "--title", "No-description ticket",
      "--criteria-file", file("c.json", JSON.generate([ "only criterion" ])))
    assert ticket["completed"], "a ticket needs no description"
  end

  def test_update_card_changes_only_given_fields_and_reads_stdin
    ok("apply-label", PARENT, "--label", "enhancement")
    list_id = ok_json("create-task-list", PARENT, "--name", "Notes")["taskList"]["id"]

    ok("update-card", PARENT, "--title", "Renamed spec", "--description-file", "-", stdin: "From stdin\nsecond line")

    detail = ok_json("show", PARENT)
    assert_equal "Renamed spec", detail["name"]
    assert_equal "From stdin\nsecond line", detail["description"]
    assert_equal [ "enhancement" ], detail["labels"].map { |l| l["name"] }, "the label was left in place"
    assert_includes detail["taskLists"].map { |l| l["id"] }, list_id, "the task list was left in place"
  end

  def test_update_card_with_nothing_to_change_fails
    _out, err, status = planka("update-card", PARENT)
    refute status.success?
    assert_includes err, "nothing to update"
  end

  def test_a_missing_required_option_fails_cleanly
    _out, err, status = planka("create-spec", "--title", "No list")
    refute status.success?
    assert_includes err, "--list is required"

    _out, err, status = planka("create-ticket", "--list", "ready-for-agent", "--title", "No criteria")
    refute status.success?
    assert_includes err, "--criteria-file is required"
  end

  def test_card_url_argument_and_custom_instance_url_are_handled
    detail = ok_json("show", "#{@server.base_url}/cards/#{PARENT}",
      env: { "PLANKA_BASE_URL" => "#{@server.base_url}///" })
    assert_equal PARENT, detail["id"]
    assert_equal "#{@server.base_url}/cards/#{PARENT}", detail["url"], "trailing slashes are stripped"
  end

  def test_an_ambiguous_list_name_is_rejected
    @server.add_list("ready-for-agent")
    _out, err, status = planka("move-card", PARENT, "--list", "ready-for-agent")
    refute status.success?
    assert_includes err, "ambiguous list name"
    assert_equal FakePlanka::LIST_READY, @server.find_card(PARENT)["listId"], "the card was not moved"
  end

  def test_missing_credentials_fail_clearly_without_leaking
    _out, err, status = planka("snapshot", env: { "PLANKA_BASE_URL" => nil })
    refute status.success?
    assert_includes err, "PLANKA_BASE_URL"
  end

  def test_no_credentials_or_tokens_appear_in_output
    out, err, _ = planka("snapshot")
    [ out, err ].each do |stream|
      refute_includes stream, PASSWORD
      refute_includes stream, "fake-token"
    end
  end

  def test_card_create_with_unknown_outcome_is_not_retried
    @server.inject("POST", %r{/api/lists/.+/cards\z}, :apply_then_drop)
    out, _err, status = planka("create-spec", "--list", "ready-for-agent", "--title", "Risky spec", "--output", "json")

    refute status.success?
    assert_equal 1, @server.cards.size - 1, "exactly one card was created"
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z}), "the create was not retried"
    doc = JSON.parse(out)
    refute doc["completed"]
    assert doc["reconcile"], "output tells the caller to reconcile by reading back"
  end

  def test_partial_ticket_creation_reports_state_and_resumes
    criteria = [ "First criterion", "Second criterion" ]
    @server.inject("POST", %r{/api/task-lists/.+/tasks\z}, :server_error, skip: 1)

    out, _err, status = planka("create-ticket", "--list", "ready-for-agent", "--title", "Half ticket",
      "--criteria-file", file("c.json", JSON.generate(criteria)), "--output", "json")
    refute status.success?
    doc = JSON.parse(out)
    card_id = doc.fetch("card").fetch("id")
    assert doc.fetch("taskList").fetch("id"), "the created task list id is reported"
    assert_equal [ "First criterion" ], doc["tasks"].map { |t| t["name"] }, "the task that landed is reported"
    refute doc["completed"]

    resumed = ok_json("create-ticket", "--card", card_id, "--criteria-file", file("c.json", JSON.generate(criteria)))
    assert resumed["completed"]
    assert_equal criteria, resumed["tasks"].map { |t| t["name"] }
    list_id = resumed["taskList"]["id"]
    assert_equal 2, @server.tasks.count { |t| t["taskListId"] == list_id }, "no duplicate task was created"
  end

  def test_transient_failures_retry_then_succeed
    @server.inject("GET", %r{/api/boards/}, :server_error, times: 2)
    ok("snapshot")
    assert_equal 3, @server.counts("GET", %r{/api/boards/}), "two retries then success"
  end

  def test_transient_failures_give_up_after_three_attempts
    @server.inject("GET", %r{/api/boards/}, :server_error, times: 5)
    _out, _err, status = planka("snapshot")
    refute status.success?
    assert_equal 3, @server.counts("GET", %r{/api/boards/}), "capped at three attempts"
  end
end
