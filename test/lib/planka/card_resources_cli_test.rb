require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class CardResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD
  BOARD = FakePlanka::BOARD_ID
  READY = FakePlanka::LIST_READY
  PROGRESS = FakePlanka::LIST_PROGRESS
  OTHER_BOARD = "100000000000000009".freeze

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, executable: "planka", stdin: "")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-password", "PLANKA_BOARD_ID" => nil }
    out, err, status = Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args,
                                      chdir: Dir.tmpdir, stdin_data: stdin)
    [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status]
  end

  def resource_writes
    @server.requests.reject { |method, path, _| method == "GET" || path.include?("access-tokens") }
  end

  def expected_card(overrides = {})
    { "id" => CARD, "name" => "Spec: Work-next refinement", "description" => "Original description.", "type" => "project",
      "boardId" => BOARD, "listId" => READY, "position" => 65_536, "createdAt" => "2026-09-01T00:00:00.000Z",
      "updatedAt" => nil }.merge(overrides)
  end

  def test_get_card_reads_one_concise_card_by_id_url_or_board_scoped_name_without_writes
    [[CARD], ["#{@server.base_url}/cards/#{CARD}"], ["Spec: Work-next refinement", "--board", BOARD]].each do |reference|
      doc, err, status = json("get", "card", *reference, env: { "PLANKA_BOARD_ID" => OTHER_BOARD })
      assert status.success?, err
      assert_equal({ "data" => expected_card, "meta" => {}, "error" => nil }, doc)
    end
    out, err, status = planka("get", "cards", CARD)
    assert status.success?, err
    assert_equal "Spec: Work-next refinement (#{CARD}) in list #{READY}", out.chomp
    assert_empty resource_writes
  end

  def ids(doc) = doc["data"].map { |card| card["id"] }

  def test_board_collection_includes_finite_and_paged_archive_cards_in_list_order
    @server.page_size = 2
    archive = @server.add_list(nil, "archive")
    archived = %w[01 02 03].map { |day| @server.add_card("Old #{day}", archive, position: nil, list_changed_at: "2026-09-#{day}T00:00:00.000Z") }
    later = @server.add_card("Later", READY, position: 131_072)
    first = @server.add_card("First", READY, position: 1)
    progress = @server.add_card("Doing", PROGRESS)
    doc, err, status = json("get", "cards", "--board", BOARD)
    assert status.success?, err
    assert_equal [first, CARD, later, progress, *archived.reverse], ids(doc)
    assert_equal({ "complete" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_equal 2, @server.counts("GET", %r{\A/api/lists/#{archive}/cards\?before}), "pages follow the native cursor until empty"
    assert_empty resource_writes
  end

  def test_list_collection_resolves_names_on_the_board_and_ids_through_their_own_board
    @server.add_card("Doing", PROGRESS)
    doc, err, status = json("get", "cards", "--list", "ready-for-agent", "--board", BOARD)
    assert status.success?, err
    assert_equal [CARD], ids(doc)
    doc, err, status = json("get", "cards", "--list", READY, env: { "PLANKA_BOARD_ID" => OTHER_BOARD })
    assert status.success?, err
    assert_equal [CARD], ids(doc)
    doc, err, status = json("get", "cards", "--list", "ready-for-agent", env: { "PLANKA_BOARD_ID" => BOARD })
    assert status.success?, err
    assert_equal [CARD], ids(doc)
    assert_empty resource_writes
  end

  def test_conflicting_or_missing_parent_scopes_fail
    @server.add_board(OTHER_BOARD)
    elsewhere = @server.add_list("elsewhere", board_id: OTHER_BOARD)
    doc, _err, status = json("get", "cards", "--list", elsewhere, "--board", BOARD)
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", doc.dig("error", "code")
    assert_equal({ "complete" => false }, doc["meta"])
    assert_match(/does not belong to --board/, doc.dig("error", "message"))
    @server.requests.clear
    _out, err, status = planka("get", "cards")
    assert_equal 2, status.exitstatus
    assert_match(/--board or --list/, err)
    _out, err, status = planka("get", "card", CARD, "--list", READY)
    assert_equal 2, status.exitstatus
    assert_match(/omitted reference/, err)
    assert_equal 0, @server.requests.size
  end

  def test_filters_combine_with_and_before_limits
    user, other = "600000000000000001", "600000000000000002"
    @server.users.push({ "id" => user, "name" => "Ada", "username" => "ada" }, { "id" => other, "name" => "Grace", "username" => nil })
    [user, other].each_with_index { |id, index| @server.board_memberships << { "id" => "70000000000000000#{index}", "boardId" => BOARD, "userId" => id } }
    @server.add_label("feature:search")
    search = @server.labels.last["id"]
    both = @server.add_card("Fix login", READY, position: 1)
    label_only = @server.add_card("Fix login", READY, position: 2)
    named_other = @server.add_card("Other", READY, position: 3)
    [both, label_only, named_other].each do |card|
      @server.card_labels.push({ "id" => "9#{card}", "cardId" => card, "labelId" => FakePlanka::LABEL_ENHANCEMENT }, { "id" => "8#{card}", "cardId" => card, "labelId" => search })
    end
    @server.memberships.push({ "id" => "81", "cardId" => both, "userId" => user }, { "id" => "82", "cardId" => both, "userId" => other },
                             { "id" => "83", "cardId" => label_only, "userId" => user }, { "id" => "84", "cardId" => named_other, "userId" => user })
    filters = ["--label", "enhancement", "--label", search, "--member", "Ada", "--name", "Fix login"]
    doc, err, status = json("get", "cards", "--board", BOARD, *filters, "--limit", "1")
    assert status.success?, err
    assert_equal [both], ids(doc)
    assert_equal false, doc.dig("meta", "complete")
    doc, err, status = json("get", "cards", "--board", BOARD, *filters, "--member", other, "--limit", "1")
    assert status.success?, err
    assert_equal [both], ids(doc)
    assert_equal true, doc.dig("meta", "complete")
    out, err, status = planka("get", "cards", "--board", BOARD, *filters, "--limit", "1")
    assert status.success?, err
    assert_includes out, "Results truncated"
    doc, _err, status = json("get", "cards", "--board", BOARD, "--label", "missing")
    assert_equal 1, status.exitstatus
    assert_equal "not_found", doc.dig("error", "code")
    _out, err, status = planka("get", "cards", "--board", BOARD, "--name", "a", "--name", "b")
    assert_equal 2, status.exitstatus
    assert_match(/Conflicting/, err)
    assert_empty resource_writes
  end

  def test_page_failure_preserves_matching_partial_results_and_reports_incomplete
    @server.page_size = 1
    trash = @server.add_list("Trash", "trash")
    kept = @server.add_card("Trashed", trash, position: nil, list_changed_at: "2026-09-02T00:00:00.000Z")
    @server.add_card("Trashed", trash, position: nil, list_changed_at: "2026-09-01T00:00:00.000Z")
    @server.inject("GET", %r{/api/lists/#{trash}/cards\?before}, :malformed_card_page)
    doc, err, status = json("get", "cards", "--board", BOARD, "--name", "Trashed")
    assert_equal 1, status.exitstatus, err
    assert_equal [kept], ids(doc)
    assert_equal false, doc.dig("meta", "complete")
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def writes = resource_writes.map { |method, path, body| [method, path, body.empty? ? nil : JSON.parse(body)] }

  def test_create_appends_a_native_card_with_the_board_default_type_and_file_description
    @server.add_card("Below", READY, position: 131_072)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "description.md")
      File.write(path, "Ünïcode \"quoted\"\nsecond line\n")
      doc, err, status = json("create", "card", "--list", "ready-for-agent", "--board", BOARD, "--name", "Fix login", "--description-file", path)
      assert status.success?, err
      card = doc["data"]
      assert_equal({ "changed" => true }, doc["meta"])
      assert_equal @server.cards.last["id"], card["id"]
      assert_equal ["Fix login", "Ünïcode \"quoted\"\nsecond line\n", "project", BOARD, READY, 131_072 + 65_536],
                   card.values_at("name", "description", "type", "boardId", "listId", "position")
      assert_equal [["POST", "/api/lists/#{READY}/cards",
                     { "type" => "project", "name" => "Fix login", "position" => 196_608, "description" => "Ünïcode \"quoted\"\nsecond line\n" }]], writes
    end
    @server.requests.clear
    out, err, status = planka("create", "cards", "--list", READY, "--name", "Top", "--position", "1", "--description-file", "-", stdin: "From stdin")
    assert status.success?, err
    assert_match(/\ACreated card Top \(\d+\) in list #{READY}/, out)
    assert_equal [["POST", "/api/lists/#{READY}/cards", { "type" => "project", "name" => "Top", "position" => 1, "description" => "From stdin" }]], writes
    assert_equal [], @server.task_lists, "no workflow criteria"
    assert_equal [], @server.memberships, "no claim"
  end

  def test_text_inputs_are_utf8_regardless_of_locale_and_invalid_utf8_is_rejected
    c_locale = { "LC_ALL" => "C", "LANG" => "C" }
    Dir.mktmpdir do |dir|
      path = File.join(dir, "description.md").tap { |file| File.write(file, "Ünïcode\n") }
      doc, err, status = json("create", "card", "--list", READY, "--name", "Café", "--description-file", path, env: c_locale)
      assert status.success?, err
      assert_equal ["Café", "Ünïcode\n"], doc["data"].values_at("name", "description")
      doc, err, status = json("update", "card", CARD, "--name", "Crème", env: c_locale)
      assert status.success?, err
      assert_equal "Crème", doc.dig("data", "name")
      invalid = File.join(dir, "invalid.md").tap { |file| File.binwrite(file, "\xFF\xFE") }
      doc, _err, status = json("create", "card", "--list", READY, "--name", "x", "--description-file", invalid)
      assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
      refute_match(/Could not read/, doc.dig("error", "message"))
      assert_equal 2, writes.size
    end
  end

  def test_create_into_archive_omits_position_and_rejects_explicit_positions
    archive = @server.add_list(nil, "archive")
    doc, err, status = json("create", "card", "--list", archive, "--board", BOARD, "--name", "Shelved")
    assert status.success?, err
    assert_nil doc.dig("data", "position")
    assert_equal [["POST", "/api/lists/#{archive}/cards", { "type" => "project", "name" => "Shelved" }]], writes
    doc, _err, status = json("create", "card", "--list", archive, "--board", BOARD, "--name", "Shelved", "--position", "5")
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", doc.dig("error", "code")
    assert_equal 1, writes.size
  end

  def test_create_and_update_validate_local_input_before_any_request
    Dir.mktmpdir do |dir|
      empty = File.join(dir, "empty.md").tap { |path| File.write(path, "") }
      [["create", "card", "--list", READY],
       ["create", "card", "--name", "x"],
       ["create", "card", "--list", READY, "--name", ""],
       ["create", "card", "--list", READY, "--name", "x" * 1025],
       ["create", "card", "--list", READY, "--name", "x", "--position", "-1"],
       ["create", "card", "--list", READY, "--name", "x", "--position", "Infinity"],
       ["create", "card", "--list", READY, "--name", "x", "--description-file", empty],
       ["create", "card", "--list", READY, "--name", "x", "--description-file", File.join(dir, "missing.md")],
       ["create", "card", CARD, "--list", READY, "--name", "x"],
       ["update", "card", CARD],
       ["update", "card", CARD, "--name", ""],
       ["update", "card", CARD, "--description-file", empty],
       ["update", "card", "--name", "x"]].each do |args|
        doc, err, status = json(*args)
        assert_equal 2, status.exitstatus, "#{args.inspect}: #{err}"
        assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
        refute_match(/unknown command/, err, args.inspect)
      end
    end
    assert_equal 0, @server.requests.size
  end

  def test_unknown_create_outcome_reports_no_invented_id_and_is_not_retried
    @server.inject("POST", %r{/api/lists/.+/cards\z}, :apply_then_drop)
    doc, _err, status = json("create", "card", "--list", READY, "--name", "Fix login")
    assert_equal 1, status.exitstatus
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "id")
    assert_equal [BOARD, READY], doc["data"].values_at("boardId", "listId")
    assert_equal({ "action" => "readback-cards", "resources" => [{ "type" => "list", "id" => READY }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/api/lists/.+/cards\z})
    @server.inject("POST", %r{/api/lists/.+/cards\z}, { "item" => { "id" => "1" } })
    doc, _err, status = json("create", "card", "--list", READY, "--name", "Malformed")
    assert_equal 1, status.exitstatus
    assert_equal "unknown_outcome", doc.dig("error", "code")
  end

  def test_update_sends_only_supplied_changed_fields_and_identical_updates_are_noops
    @server.card_labels << { "id" => "91", "cardId" => CARD, "labelId" => FakePlanka::LABEL_ENHANCEMENT }
    doc, err, status = json("update", "card", CARD, "--name", "Renamed")
    assert status.success?, err
    assert_equal expected_card("name" => "Renamed"), doc["data"]
    assert_equal({ "changed" => true }, doc["meta"])
    assert_equal [["PATCH", "/api/cards/#{CARD}", { "name" => "Renamed" }]], writes
    @server.requests.clear
    out, err, status = planka("update", "cards", "Renamed", "--board", BOARD, "--description-file", "-", stdin: "New\ntext")
    assert status.success?, err
    assert_equal "Updated card Renamed (#{CARD}) in list #{READY}", out.chomp
    assert_equal [["PATCH", "/api/cards/#{CARD}", { "description" => "New\ntext" }]], writes
    @server.requests.clear
    doc, err, status = json("update", "card", CARD, "--name", "Renamed", "--description-file", "-", stdin: "New\ntext")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_empty writes
    assert_equal [READY, 65_536], @server.find_card(CARD).values_at("listId", "position")
    assert_equal 1, @server.card_labels.size, "unrelated card data is preserved"
  end

  def test_update_failures_distinguish_rejected_from_unknown_outcomes
    @server.inject("PATCH", %r{/api/cards/}, 403)
    doc, _err, status = json("update", "card", CARD, "--name", "Renamed")
    assert_equal 1, status.exitstatus
    assert_equal ["authorization_error", false, expected_card], [doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
    @server.inject("PATCH", %r{/api/cards/}, { "item" => { "id" => CARD } })
    doc, _err, status = json("update", "card", CARD, "--name", "Renamed")
    assert_equal 1, status.exitstatus
    assert_equal ["unknown_outcome", nil], [doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal expected_card("name" => nil), doc["data"]
    assert_equal({ "action" => "readback-card", "resources" => [{ "type" => "card", "id" => CARD }] }, doc.dig("error", "recovery"))
  end

  def test_move_appends_within_the_cards_own_board_and_preserves_card_data
    @server.add_card("Doing", PROGRESS, position: 200_000)
    @server.memberships << { "id" => "81", "cardId" => CARD, "userId" => "600000000000000001" }
    doc, err, status = json("move", "card", CARD, "--list", "in-progress", env: { "PLANKA_BOARD_ID" => OTHER_BOARD })
    assert status.success?, err
    assert_equal expected_card("listId" => PROGRESS, "position" => 265_536), doc["data"]
    assert_equal({ "changed" => true }, doc["meta"])
    assert_equal [["PATCH", "/api/cards/#{CARD}", { "listId" => PROGRESS, "position" => 265_536 }]], writes
    assert_equal 1, @server.memberships.size, "moving does not claim or unclaim"
    @server.requests.clear
    doc, err, status = json("move", "cards", CARD, "--list", PROGRESS)
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed"), "moving to the current list without --position is a no-op"
    assert_empty writes
    out, err, status = planka("move", "card", CARD, "--list", PROGRESS, "--position", "1")
    assert status.success?, err
    assert_equal "Moved card Spec: Work-next refinement (#{CARD}) in list #{PROGRESS}", out.chomp
    assert_equal [["PATCH", "/api/cards/#{CARD}", { "position" => 1 }]], writes, "a same-list reposition sends only position"
  end

  def test_move_to_archive_sends_no_position_and_scope_mismatches_fail
    archive = @server.add_list(nil, "archive")
    doc, err, status = json("move", "card", CARD, "--list", archive)
    assert status.success?, err
    assert_equal [archive, nil], doc["data"].values_at("listId", "position")
    assert_equal [["PATCH", "/api/cards/#{CARD}", { "listId" => archive, "position" => nil }]], writes
    @server.add_board(OTHER_BOARD)
    elsewhere = @server.add_list("elsewhere", board_id: OTHER_BOARD)
    [[CARD, "--list", elsewhere], [CARD, "--list", READY, "--board", OTHER_BOARD], [CARD, "--list", READY, "--position", "-2"],
     [CARD], [CARD, "--list", archive, "--position", "3"]].each do |args|
      doc, _err, status = json("move", "card", *args)
      assert_equal 2, status.exitstatus, args.inspect
      assert_equal "invalid_input", doc.dig("error", "code"), args.inspect
    end
    assert_equal 1, writes.size
  end

  def test_delete_issues_one_target_deletion_and_leaves_linked_cards
    blocked = @server.add_card("Blocked", READY)
    @server.task_lists << { "id" => "910", "cardId" => blocked, "name" => "Blockers" }
    @server.tasks << { "id" => "911", "taskListId" => "910", "name" => "Spec", "linkedCardId" => CARD, "isCompleted" => false }
    doc, err, status = json("delete", "card", "Spec: Work-next refinement", "--board", BOARD)
    assert status.success?, err
    assert_equal expected_card("deleted" => true), doc["data"]
    assert_equal({ "changed" => true }, doc["meta"])
    assert_equal [["DELETE", "/api/cards/#{CARD}", nil]], writes
    assert_nil @server.find_card(CARD)
    refute_nil @server.find_card(blocked), "linked cards are never deleted"
    out, err, status = planka("delete", "cards", blocked)
    assert status.success?, err
    assert_equal "Deleted card Blocked (#{blocked}) from list #{READY}", out.chomp
  end

  def test_delete_requires_a_target_and_reports_rejected_or_unknown_outcomes
    doc, _err, status = json("delete", "card")
    assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
    assert_equal 0, @server.requests.size
    @server.inject("DELETE", %r{/api/cards/}, 403)
    doc, _err, status = json("delete", "card", CARD)
    assert_equal [1, "authorization_error", false, expected_card], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
    @server.inject("DELETE", %r{/api/cards/}, :apply_then_drop)
    doc, _err, status = json("delete", "card", CARD)
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal expected_card("deleted" => nil), doc["data"]
    assert_equal({ "action" => "readback-card", "resources" => [{ "type" => "card", "id" => CARD }] }, doc.dig("error", "recovery"))
    assert_equal 2, @server.counts("DELETE", %r{/api/cards/}), "the unknown delete is not retried"
  end

  def test_help_is_offline_at_root_group_and_leaf_levels
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    { [] => "get cards --board BOARD|--list LIST", %w[--help] => "delete card CARD",
      %w[get --help] => "cards --board BOARD|--list LIST", %w[create --help] => "card --list LIST --name NAME",
      %w[update --help] => "card CARD  Change only supplied card fields", %w[move --help] => "card CARD --list LIST",
      %w[delete --help] => "card CARD  Delete one card", %w[get cards --help] => "usage: planka get cards",
      %w[get card -h] => "planka get card CARD", %w[create cards --help] => "usage: planka create card",
      %w[update card --help] => "usage: planka update card CARD", %w[move cards -h] => "usage: planka move card CARD",
      %w[delete card --help] => "usage: planka delete card CARD" }.each do |args, text|
      out, err, status = planka(*args, env: offline)
      assert status.success?, "#{args.inspect}: #{err}"
      assert_includes out, text, args.inspect
    end
    assert_equal 0, @server.requests.size
  end

  def test_legacy_card_commands_name_implemented_replacements_and_keep_their_contracts
    { "planka-update-card" => "planka update card CARD", "planka-move-card" => "planka move card CARD --list LIST",
      "planka-snapshot" => "planka get cards --list LIST" }.each do |executable, replacement|
      out, err, status = planka("--help", executable: executable)
      assert status.success?, err
      assert_includes out, replacement
      refute_includes out, "not yet implemented"
    end
    out, err, status = planka("update-card", CARD, "--title", "Legacy", "--output", "json")
    assert status.success?, err
    assert_equal({ "card" => { "id" => CARD, "name" => "Legacy", "description" => "Original description.", "listId" => READY, "position" => 65_536 } }, JSON.parse(out))
    out, err, status = planka("move-card", CARD, "--list", "in-progress", "--output", "json")
    assert status.success?, err
    assert_equal PROGRESS, JSON.parse(out).dig("card", "listId")
    out, err, status = planka("snapshot", "--board", BOARD, "--list", "in-progress", "--output", "json")
    assert status.success?, err
    assert_equal [BOARD, PROGRESS, [CARD]], [JSON.parse(out)["boardId"], JSON.parse(out)["listId"], JSON.parse(out)["cards"].map { |card| card["id"] }]
  end
end
