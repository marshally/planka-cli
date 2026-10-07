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
end
