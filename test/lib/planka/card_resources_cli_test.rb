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
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args,
                   chdir: Dir.tmpdir, stdin_data: stdin)
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
end
