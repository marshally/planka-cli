require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"
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
    invocations = [ ["describe"], ["describe", "card"], ["describe", "board", PARENT],
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
      board = Planka::Board.new(client.board(@server.board_id), base_url: @server.base_url)
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
