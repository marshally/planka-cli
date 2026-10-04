require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"

class Planka::WorkflowNextCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  BOARD = FakePlanka::BOARD_ID

  def setup
    @server = FakePlanka.new
  end

  def teardown
    @server.stop
  end

  def planka(*args, env: {})
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
      "PLANKA_AGENT_PASSWORD" => "fake-next-password", "PLANKA_BOARD_ID" => BOARD,
      "PLANKA_BRANCH_PREFIX" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
  end

  def test_empty_queue_is_canonical_success_and_only_reads_the_explicit_board
    out, err, status = planka("workflow", "next", "--board", BOARD, "-o", "json",
      env: { "PLANKA_BOARD_ID" => "999999" })
    assert status.success?, err
    assert_empty err
    assert_equal({ "data" => { "card" => nil, "waiting" => [] }, "meta" => {}, "error" => nil }, JSON.parse(out))
    assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/boards/#{BOARD}"],
      ["DELETE", "/api/access-tokens/me"]], @server.requests.map { |method, path, _| [method, path] }
  end
  def test_priority_pick_preserves_legacy_human_and_json_reports
    id = "400000000000000002"
    @server.cards << @server.cards.first.merge("id" => id, "name" => "Implement search", "position" => 1)
    @server.task_lists << { "id" => "600000000000000001", "cardId" => id, "name" => "Acceptance criteria", "position" => 1 }
    out, err, status = planka("workflow", "next", "-o", "json")
    assert status.success?, err
    data = JSON.parse(out).fetch("data")
    assert_equal({"card" => {"id" => id, "name" => "Implement search", "url" => "#{@server.base_url}/cards/#{id}"},
      "specs" => [], "number" => nil, "blockers" => [], "parent" => "main"}, data)
    legacy, err, status = planka("next-card", "--output", "json")
    assert status.success?, err
    assert_equal JSON.parse(legacy), data
    human, err, status = planka("workflow", "next")
    assert status.success?, err
    assert_equal "card: Implement search (#{@server.base_url}/cards/#{id})\nspec: none\nblockers: none\nparent: main\n", human
    legacy, err, status = planka("next-card")
    assert status.success?, err
    assert_equal legacy, human
  end

  def ticket(id, name, position: 1, created_at: "2026-09-01T00:00:00Z")
    @server.cards << @server.cards.first.merge("id" => id, "name" => name, "position" => position, "createdAt" => created_at)
    @server.task_lists << { "id" => "6#{id}", "cardId" => id, "name" => "Acceptance criteria", "position" => 1 }
    id
  end

  def label(name, *cards)
    id = (300000000000000010 + @server.labels.size).to_s
    @server.labels << { "id" => id, "name" => name, "boardId" => BOARD }
    cards.each { |card| @server.card_labels << { "cardId" => card, "labelId" => id } }
  end

  def test_repeated_labels_and_match_before_feature_selection_and_unknown_labels_are_empty
    first = ticket("400000000000000002", "First", position: 99)
    second = ticket("400000000000000003", "Second", created_at: "2026-09-02T00:00:00Z")
    label("feature:search", first, second, FakePlanka::PARENT_CARD)
    label("enhancement", second)
    out, err, status = planka("workflow", "next", "--label", "enhancement", "--label", "feature:search", "-o", "json")
    assert status.success?, err
    assert_equal second, JSON.parse(out).dig("data", "card", "id")
    assert_equal 1, JSON.parse(out).dig("data", "number")
    out, err, status = planka("workflow", "next", "--label", "feature:missing", "-o", "json")
    assert status.success?, err
    assert_equal({"card" => nil, "waiting" => []}, JSON.parse(out).fetch("data"))
    out, err, status = planka("workflow", "next", "--label", "enhancement", "-o", "json")
    assert status.success?, err
    assert_equal second, JSON.parse(out).dig("data", "card", "id")
    assert_nil JSON.parse(out).dig("data", "number")
  end

  def test_malformed_selection_records_fail_instead_of_claiming_an_empty_queue
    @server.inject("GET", %r{boards/#{BOARD}$}, :missing_board_records)
    out, err, status = planka("workflow", "next", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes err, "KeyError"
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_malformed_ticket_position_is_a_sanitized_api_error
    id = ticket("400000000000000002", "Bad ticket")
    @server.find_card(id)["position"] = "private-invalid-position"
    out, err, status = planka("workflow", "next", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes out + err, "private-invalid-position"
  end

  def test_invalid_task_completion_cannot_make_a_blocked_ticket_takeable
    id = ticket("400000000000000002", "Blocked")
    @server.tasks << { "id" => "700000000000000001", "taskListId" => "6#{id}", "name" => "Depends",
      "linkedCardId" => FakePlanka::PARENT_CARD, "isCompleted" => "private-invalid-boolean" }
    out, err, status = planka("workflow", "next", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_includes out + err, "private-invalid-boolean"
  end

  def test_malformed_board_identity_and_associations_do_not_produce_a_queue_result
    id = ticket("400000000000000002", "Ticket")
    label("feature:search", id)
    @server.memberships << { "cardId" => id, "userId" => "user-bot" }
    @server.tasks << { "id" => "700000000000000001", "taskListId" => "6#{id}", "name" => "Depends",
      "linkedCardId" => FakePlanka::PARENT_CARD, "isCompleted" => true }
    collections = [@server.cards, @server.lists, @server.labels, @server.card_labels, @server.task_lists, @server.tasks, @server.memberships]
    baseline = Marshal.dump(collections)
    mutations = [
      -> { @server.memberships.first["userId"] = 42 },
      -> { @server.memberships.first["cardId"] = "999" },
      -> { @server.cards.last["id"] = "../users/me" },
      -> { @server.cards.last["name"] = 42 },
      -> { @server.cards.last["createdAt"] = "private-invalid-date" },
      -> { @server.cards.last["listId"] = "999" },
      -> { @server.cards << @server.cards.last.dup },
      -> { @server.lists.first["type"] = "private-invalid-type" },
      -> { @server.lists.first["name"] = 42 },
      -> { @server.labels.last["name"] = 42 },
      -> { @server.card_labels.first["labelId"] = "999" },
      -> { @server.task_lists.first["name"] = 42 },
      -> { @server.tasks.first["linkedCardId"] = "999" },
      -> { @server.tasks.first["taskListId"] = "999" }
    ]
    mutations.each_with_index do |mutate, index|
      restored = Marshal.load(baseline)
      collections.zip(restored).each { |collection, original| collection.replace(original) }
      mutate.call
      @server.inject("GET", %r{boards/#{BOARD}$}, { "included" =>
        %w[cards lists labels cardLabels taskLists tasks cardMemberships].zip(collections).to_h })
      out, err, status = planka("workflow", "next", "--label", "feature:search", "-o", "json")
      assert_equal 1, status.exitstatus, "mutation #{index}: #{out} #{err}"
      assert_equal "api_error", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "private-invalid"
      refute_match(/KeyError|TypeError|NoMethodError/, err)
    end
  end

  def test_invalid_scope_and_labels_are_canonical_errors_before_authentication
    [["--board", ""], ["--board", "123", "--board", "456"], ["--label", ""],
      ["--label", "feature:a", "--label", "effort:b"], ["--label", "feature:a", "--label", "feature:b"],
      ["--board", "https://other.example/boards/123"], ["--board", "../users/me"], ["extra"], ["--limit", "1"]].each do |suffix|
      out, err, status = planka("-o", "json", "workflow", "next", *suffix)
      assert_equal 2, status.exitstatus, "#{suffix}: #{out} #{err}"
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      assert_match(/planka workflow(?: next)?:/, err)
      assert_empty @server.requests
    end
  end

  def blocked_ticket
    id = ticket("400000000000000002", "Stacked ticket")
    @server.tasks << { "id" => "700000000000000001", "taskListId" => "6#{id}", "name" => "Depends",
      "linkedCardId" => FakePlanka::PARENT_CARD, "isCompleted" => true }
    id
  end

  def test_malformed_blocker_comments_fail_as_sanitized_api_errors
    blocked_ticket
    @server.inject("GET", %r{cards/#{FakePlanka::PARENT_CARD}/comments$}, :malformed_comments)
    out, err, status = planka("workflow", "next", "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out)["data"]
    refute_match(/TypeError|NoMethodError/, err)
  end

  def with_gh(output: '{"state":"OPEN","headRefName":"feature/stack"}', exit_code: "0")
    Dir.mktmpdir("planka-next-gh-") do |dir|
      File.write(File.join(dir, "gh"), <<~SCRIPT)
        #!/usr/bin/env ruby
        require "json"
        File.open(ENV.fetch("NEXT_GH_CALLS"), "a") { |file| file.puts JSON.generate(ARGV) }
        warn "private-gh-diagnostic" unless ENV.fetch("NEXT_GH_EXIT") == "0"
        puts ENV.fetch("NEXT_GH_OUTPUT")
        exit ENV.fetch("NEXT_GH_EXIT").to_i
      SCRIPT
      File.chmod(0755, File.join(dir, "gh"))
      calls = File.join(dir, "calls.jsonl")
      settings = { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "NEXT_GH_OUTPUT" => output,
        "NEXT_GH_EXIT" => exit_code, "NEXT_GH_CALLS" => calls }
      yield settings, calls
    end
  end

  def add_handoff(text)
    @server.comments << { "id" => "500000000000000002", "cardId" => FakePlanka::PARENT_CARD,
      "text" => text, "createdAt" => "2026-10-04T10:00:00Z" }
  end

  def test_malformed_github_results_are_sanitized_instead_of_guessing_a_parent
    blocked_ticket
    add_handoff("Branch: recorded/branch\nPR: https://github.com/example/repo/pull/1")
    with_gh(output: 'private-invalid-json') do |settings, calls|
      out, err, status = planka("workflow", "next", "-o", "json", env: settings)
      assert_equal 1, status.exitstatus
      assert_equal "api_error", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "private-invalid-json"
      assert_equal ["pr", "view", "https://github.com/example/repo/pull/1", "--json", "state,headRefName"], JSON.parse(File.read(calls))
    end
  end

  def test_github_response_shape_and_states_are_validated
    blocked_ticket
    add_handoff("Branch: recorded/branch\nPR: https://github.com/example/repo/pull/1")
    ['{"state":"private-invalid-state","headRefName":"branch"}', '{"state":"OPEN","headRefName":42}', '[]'].each do |response|
      with_gh(output: response) do |settings, _calls|
        out, err, status = planka("workflow", "next", "-o", "json", env: settings)
        assert_equal 1, status.exitstatus
        assert_equal "api_error", JSON.parse(out).dig("error", "code")
        assert_nil JSON.parse(out)["data"]
        refute_includes out + err, "private-invalid"
      end
    end
  end

  def test_feature_creation_order_waiting_and_effort_frontier_reuse_legacy_rules
    first = ticket("400000000000000002", "First", position: 99)
    second = ticket("400000000000000003", "Second", position: 1, created_at: "2026-09-02T00:00:00Z")
    label("feature:search", first, second, FakePlanka::PARENT_CARD)
    out, err, status = planka("workflow", "next", "--label", "feature:search", "-o", "json")
    assert status.success?, err
    assert_equal first, JSON.parse(out).dig("data", "card", "id")
    assert_equal 1, JSON.parse(out).dig("data", "number")
    assert_equal [FakePlanka::PARENT_CARD], JSON.parse(out).dig("data", "specs").map { |card| card["id"] }
    legacy, err, status = planka("next-card", "feature:search", "--output", "json")
    assert status.success?, err
    assert_equal JSON.parse(legacy), JSON.parse(out)["data"]
    @server.memberships << { "cardId" => first, "userId" => "someone" }
    @server.tasks << { "id" => "700000000000000001", "taskListId" => "6#{second}", "linkedCardId" => first, "isCompleted" => false }
    out, err, status = planka("workflow", "next", "--label", "feature:search", "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out).dig("data", "card")
    waiting = JSON.parse(out).dig("data", "waiting")
    assert_equal [first, second], waiting.map { |card| card["id"] }
    assert_equal true, waiting.first["claimed"]
    assert_equal [first], waiting.last["blockedBy"].map { |card| card["id"] }
    @server.tasks.clear
    label("effort:search", first, second, FakePlanka::PARENT_CARD)
    label("wayfinder:map", FakePlanka::PARENT_CARD)
    out, err, status = planka("workflow", "next", "--label", "effort:search", "-o", "json")
    assert status.success?, err
    assert_equal second, JSON.parse(out).dig("data", "card", "id")
    assert_equal [second], JSON.parse(out).dig("data", "frontier").map { |card| card["id"] }
    assert_equal [FakePlanka::PARENT_CARD], JSON.parse(out).dig("data", "maps").map { |card| card["id"] }
    legacy, err, status = planka("next-card", "effort:search", "--output", "json")
    assert status.success?, err
    assert_equal JSON.parse(legacy), JSON.parse(out)["data"]
  end

  def test_blocker_handoffs_and_github_states_preserve_stacking_and_failed_lookup_is_unknown
    id = blocked_ticket
    label("feature:search", id)
    add_handoff("Branch: recorded/branch\nPR: https://github.com/example/repo/pull/1")
    [{"state" => "OPEN", "headRefName" => "feature/stack"}, {"state" => "MERGED", "headRefName" => "feature/stack"},
      {"state" => "CLOSED", "headRefName" => "feature/stack"}].each do |pr|
      with_gh(output: JSON.generate(pr)) do |settings, calls|
        out, err, status = planka("workflow", "next", "--label", "feature:search", "-o", "json", env: settings)
        assert status.success?, err
        assert_empty err
        data = JSON.parse(out)["data"]
        assert_equal pr["state"] == "MERGED" ? "main" : "feature/stack", data["parent"]
        assert_equal pr["state"], data["blockers"].first["pullRequestState"]
        assert_equal FakePlanka::PARENT_CARD, data["blockers"].first.dig("card", "id")
        assert_equal 1, File.readlines(calls).size
        legacy, err, status = planka("next-card", "feature:search", "--output", "json", env: settings)
        assert status.success?, err
        assert_equal JSON.parse(legacy), data
      end
    end
    with_gh(exit_code: "1") do |settings, _calls|
      out, err, status = planka("workflow", "next", "-o", "json", env: settings)
      assert status.success?, err
      assert_empty err
      assert_equal "recorded/branch", JSON.parse(out).dig("data", "parent")
      assert_nil JSON.parse(out).dig("data", "blockers").first["pullRequestState"]
    end
    add_handoff("Branch: latest/only")
    @server.comments.last["createdAt"] = "2026-10-04T11:00:00Z"
    with_gh do |settings, calls|
      out, err, status = planka("workflow", "next", "-o", "json", env: settings)
      assert status.success?, err
      assert_equal "latest/only", JSON.parse(out).dig("data", "parent")
      refute File.exist?(calls), "latest branch-only handoff needs no GitHub request"
    end
  end

  def test_missing_github_executable_reports_a_configuration_failure_and_cleans_up
    blocked_ticket
    add_handoff("Branch: recorded/branch\nPR: https://github.com/example/repo/pull/1")
    Dir.mktmpdir do |empty_path|
      out, err, status = planka("workflow", "next", "-o", "json", env: {"PATH" => empty_path})
      assert_equal 1, status.exitstatus
      assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
      assert_includes err, "gh"
      assert_nil JSON.parse(out)["data"]
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
  end

  def test_scope_defaults_urls_connection_settings_flags_and_errors_precede_network
    out, err, status = planka("-o", "json", "workflow", "--board", "#{@server.base_url}/boards/#{BOARD}/", "next",
      env: { "PLANKA_BOARD_ID" => nil, "PLANKA_BRANCH_PREFIX" => "x" * 60 })
    assert status.success?, err
    assert_nil JSON.parse(out).dig("data", "card")
    @server.requests.clear
    %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD PLANKA_BOARD_ID].each do |key|
      [nil, ""].each do |value|
        out, err, status = planka("workflow", "next", "-o", "json", env: {key => value})
        assert_equal 1, status.exitstatus
        assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
        assert_includes err, key
        assert_empty @server.requests
      end
    end
    out, err, status = planka("workflow", "guide", "--board", BOARD, "-o", "json")
    assert_equal 2, status.exitstatus
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_empty @server.requests
  end

  def test_api_failures_and_cleanup_failures_preserve_the_primary_result
    [401, 403, 404, 500].zip(%w[authentication_error authorization_error not_found api_error]).each do |http, code|
      @server.inject("GET", %r{boards/#{BOARD}$}, http, times: http == 500 ? 3 : 1)
      @server.inject("DELETE", %r{access-tokens/me$}, 403)
      out, err, status = planka("workflow", "next", "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out)["data"]
      refute_includes out + err, "private upstream body"
      assert_includes err, "session cleanup failed"
    end
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "next", "-o", "json")
    assert status.success?, err
    assert_equal({"card" => nil, "waiting" => []}, JSON.parse(out)["data"])
    assert_nil JSON.parse(out)["error"]
    assert_includes err, "planka workflow next: session cleanup failed"
  end

  def test_no_handoff_and_multiple_unmerged_blockers_remain_ambiguous
    blocked_ticket
    out, err, status = planka("workflow", "next", "-o", "json")
    assert status.success?, err
    assert_includes JSON.parse(out).dig("data", "parent"), "AMBIGUOUS: no Branch: comment"
    add_handoff("Branch: one")
    other = "400000000000000003"
    @server.cards << @server.cards.first.merge("id" => other, "name" => "Other blocker")
    @server.comments << {"cardId" => other, "text" => "Branch: two", "createdAt" => "2026-10-04T10:00:00Z"}
    @server.tasks << @server.tasks.first.merge("id" => "700000000000000002", "linkedCardId" => other)
    out, err, status = planka("workflow", "next", "-o", "json")
    assert status.success?, err
    assert_equal "AMBIGUOUS: unmerged blockers one, two", JSON.parse(out).dig("data", "parent")
  end

  def test_invalid_default_board_is_configuration_error_without_network
    out, err, status = planka("workflow", "next", "-o", "json", env: {"PLANKA_BOARD_ID" => "private-invalid-board"})
    assert_equal 1, status.exitstatus
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_includes err, "PLANKA_BOARD_ID"
    refute_includes out + err, "private-invalid-board"
    assert_empty @server.requests
  end

end
