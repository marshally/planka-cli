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
end
