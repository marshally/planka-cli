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

  def ok(*args, **kwargs)
    out, err, status = planka(*args, **kwargs)
    assert status.success?, "#{args.inspect} failed (#{err})"
    out
  end

  def ok_json(*args, **kwargs) = JSON.parse(ok(*args, **kwargs))

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
    out, _err, status = planka("create-spec", "--list", "ready-for-agent", "--title", "Risky spec")

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
      "--criteria-file", file("c.json", JSON.generate(criteria)))
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
