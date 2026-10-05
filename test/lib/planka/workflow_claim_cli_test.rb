require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"

class Planka::WorkflowClaimCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
      "PLANKA_AGENT_PASSWORD" => "fake-claim-password", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args, chdir: Dir.tmpdir)
  end

  def test_claim_adds_membership_then_moves_the_card_and_reports_both_effects
    out, err, status = planka("workflow", "claim", "#{@server.base_url}/cards/#{CARD}", "-o", "json")
    assert status.success?, err
    assert_empty err
    doc = JSON.parse(out)
    assert_equal({ "changed" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_equal({ "card" => { "id" => CARD, "name" => "Spec: Work-next refinement",
      "listId" => FakePlanka::LIST_PROGRESS, "position" => 65_535, "url" => "#{@server.base_url}/cards/#{CARD}" },
      "userId" => "user-bot", "inProgressListId" => FakePlanka::LIST_PROGRESS,
      "membershipId" => "1900000000000000001", "claimed" => true, "memberAdded" => true, "moved" => true }, doc["data"])
    writes = @server.requests.select { |method, path, _| method == "PATCH" || path.end_with?("card-memberships") }
    assert_equal [["POST", "/api/cards/#{CARD}/card-memberships", { "userId" => "user-bot" }],
      ["PATCH", "/api/cards/#{CARD}", { "listId" => FakePlanka::LIST_PROGRESS, "position" => 65_535 }]],
      writes.map { |method, path, body| [method, path, JSON.parse(body)] }
    read, read_err, read_status = planka("describe", "card", CARD, "-o", "json")
    assert read_status.success?, read_err
    assert_includes read, FakePlanka::LIST_PROGRESS
    assert_includes read, "user-bot"
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_a_move_response_from_another_board_preserves_membership_and_reports_unknown_move
    @server.inject("PATCH", %r{/cards/#{CARD}$}, { "item" => @server.find_card(CARD).merge(
      "listId" => FakePlanka::LIST_PROGRESS, "boardId" => "999") })
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    doc = JSON.parse(out)
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal true, doc.dig("data", "memberAdded")
    assert_nil doc.dig("data", "moved")
    assert_equal FakePlanka::LIST_READY, doc.dig("data", "card", "listId")
  end

  def test_reclaim_is_a_noop_and_does_not_reposition_or_duplicate_membership
    _out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    @server.find_card(CARD)["position"] = 42
    @server.requests.clear
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    doc = JSON.parse(out)
    assert_equal false, doc.dig("meta", "changed")
    assert_equal false, doc.dig("data", "memberAdded")
    assert_equal false, doc.dig("data", "moved")
    assert_equal 42, doc.dig("data", "card", "position")
    assert_empty resource_writes
    assert_equal 1, @server.memberships.size
  end

  def test_existing_membership_only_moves_and_existing_progress_only_adds_membership
    @server.memberships << { "id" => "999", "cardId" => CARD, "userId" => "user-bot" }
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    assert_equal ["PATCH"], resource_writes.map(&:first)
    assert_equal false, JSON.parse(out).dig("data", "memberAdded")
    @server.memberships.clear
    @server.find_card(CARD)["position"] = 123
    @server.requests.clear
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    assert_equal ["POST"], resource_writes.map(&:first)
    assert_equal false, JSON.parse(out).dig("data", "moved")
    assert_equal 123, JSON.parse(out).dig("data", "card", "position")
  end

  def test_move_rejection_preserves_membership_and_reports_partial_failure_without_rollback
    @server.inject("PATCH", %r{/cards/#{CARD}$}, 403)
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "partial_failure", doc.dig("error", "code")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal true, doc.dig("data", "claimed")
    assert_equal true, doc.dig("data", "memberAdded")
    assert_equal false, doc.dig("data", "moved")
    assert_equal "1900000000000000001", doc.dig("data", "membershipId")
    assert_equal({ "action" => "readback-claim", "resources" => [{ "type" => "card", "id" => CARD }] }, doc.dig("error", "recovery"))
    assert_includes err, "HTTP 403"
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    refute_includes out + err, "private upstream body"
    read, err, status = planka("describe", "card", CARD, "-o", "json")
    assert status.success?, err
    assert_includes read, "user-bot"
    assert_equal FakePlanka::LIST_READY, JSON.parse(read).dig("data", "listId")
  end

  def test_unknown_membership_is_not_retried_and_readback_allows_safe_completion
    @server.inject("POST", %r{card-memberships$}, :apply_then_drop)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "memberAdded")
    assert_nil doc.dig("data", "claimed")
    assert_equal false, doc.dig("data", "moved")
    assert_equal ["POST"], resource_writes.map(&:first)
    read, err, status = planka("describe", "card", CARD, "-o", "json")
    assert status.success?, err
    assert_includes read, "user-bot"
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("data", "memberAdded")
    assert_equal 1, @server.memberships.size
  end

  def test_unknown_move_keeps_known_membership_and_readback_can_confirm_the_move
    @server.inject("PATCH", %r{/cards/#{CARD}$}, :apply_then_drop)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_equal true, doc.dig("meta", "changed")
    assert_equal true, doc.dig("data", "memberAdded")
    assert_nil doc.dig("data", "moved")
    assert_equal 1, resource_writes.count { |method, _, _| method == "PATCH" }
    read, err, status = planka("describe", "card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal FakePlanka::LIST_PROGRESS, JSON.parse(read).dig("data", "listId")
    @server.requests.clear
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("meta", "changed")
    assert_empty resource_writes
  end

  def test_rejected_first_write_reports_unchanged_and_preserves_the_primary_category
    @server.inject("POST", %r{card-memberships$}, 403)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    doc = JSON.parse(out)
    assert_equal "authorization_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_equal false, doc.dig("data", "claimed")
    assert_equal ["POST"], resource_writes.map(&:first)
    refute_includes out + err, "private upstream body"
  end

  def test_missing_or_ambiguous_progress_lists_fail_before_writes
    @server.lists.delete_if { |list| list["name"] == "in-progress" }
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_equal false, JSON.parse(out).dig("meta", "changed")
    assert_includes err, "exactly one in-progress list"
    @server.add_list("in-progress")
    @server.add_list("in-progress")
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_empty resource_writes
  end

  def test_malformed_reads_fail_before_writes_and_malformed_writes_report_uncertainty
    [["GET", %r{users/me$}, :malformed_user], ["GET", %r{users/me$}, {}], ["GET", %r{/cards/#{CARD}$}, :malformed_card],
      ["GET", %r{boards/.+$}, :malformed_board]].each do |method, path, payload|
      @server.inject(method, path, payload)
      out, err, status = planka("workflow", "claim", CARD, "-o", "json")
      assert_equal 1, status.exitstatus, out + err
      assert_equal "api_error", JSON.parse(out).dig("error", "code")
      assert_equal false, JSON.parse(out).dig("meta", "changed")
      assert_empty resource_writes
      refute_match(/KeyError|NoMethodError|TypeError/, out + err)
    end
    @server.inject("POST", %r{card-memberships$}, { "item" => nil })
    out, _err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "unknown_outcome", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out).dig("meta", "changed")
    assert_equal ["POST"], resource_writes.map(&:first)
  end

  def test_help_and_local_errors_never_authenticate
    [["workflow", "claim", "--help"], ["workflow", "--help"], ["--help"]].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_AGENT_PASSWORD" => nil })
      assert status.success?, err
      assert_includes out, "claim CARD"
    end
    [[[], {}], [[CARD, "extra"], {}], [[CARD, "--board", "123"], {}],
      [["https://other.example/cards/#{CARD}"], {}], [["../users/me"], {}]].each do |args, env|
      out, err, status = planka("-o", "json", "workflow", "claim", *args, env: env)
      assert_equal 2, status.exitstatus, out + err
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    end
    out, _err, status = planka("workflow", "claim", CARD, "-o", "json", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert_equal 1, status.exitstatus
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_equal false, JSON.parse(out).dig("meta", "changed")
    assert_empty @server.requests
  end

  def test_human_output_and_success_survive_cleanup_failure
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "claim", CARD)
    assert status.success?, err
    assert_equal "claimed: Spec: Work-next refinement (#{@server.base_url}/cards/#{CARD})\nmember added: true\nmoved: true\n", out
    assert_includes err, "session cleanup failed; the operation result is unchanged"
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert status.success?, err
    assert_nil JSON.parse(out)["error"]
    assert_equal false, JSON.parse(out).dig("meta", "changed")
  end

  def test_legacy_flat_and_direct_claim_keep_their_bare_json_and_reposition_behavior
    [nil, "planka-claim"].each do |executable|
      args = executable ? [CARD, "--output", "json"] : ["claim", CARD, "--output", "json"]
      out, err, status = planka(*args, executable: executable || "planka")
      assert status.success?, err
      assert_empty err
      doc = JSON.parse(out)
      assert_equal %w[card claimed memberAdded], doc.keys.sort
      assert_equal true, doc["claimed"]
      assert_equal 65_535, doc.dig("card", "position")
      @server.find_card(CARD)["position"] = 42
    end
  end

  def resource_writes
    @server.requests.select { |method, path, _| method == "PATCH" || path.end_with?("card-memberships") }
  end

  def test_authentication_and_read_errors_preserve_categories_without_effects
    [["POST", %r{access-tokens$}, 401, "authentication_error"],
      ["GET", %r{/cards/#{CARD}$}, 404, "not_found"],
      ["GET", %r{boards/.+$}, 403, "authorization_error"],
      ["GET", %r{users/me$}, 422, "api_error"]].each do |method, path, http_status, code|
      @server.inject(method, path, http_status)
      out, err, status = planka("workflow", "claim", CARD, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal code, JSON.parse(out).dig("error", "code")
      assert_equal false, JSON.parse(out).dig("meta", "changed")
      assert_empty resource_writes
      refute_includes out + err, "private upstream body"
    end
  end

  def test_move_server_error_with_existing_membership_has_unknown_effect_and_is_not_retried
    @server.memberships << { "id" => "999", "cardId" => CARD, "userId" => "user-bot" }
    @server.inject("PATCH", %r{/cards/#{CARD}$}, :server_error)
    out, err, status = planka("workflow", "claim", CARD, "-o", "json")
    assert_equal 1, status.exitstatus
    assert_equal "unknown_outcome", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out).dig("meta", "changed")
    assert_equal true, JSON.parse(out).dig("data", "claimed")
    assert_nil JSON.parse(out).dig("data", "moved")
    assert_equal 1, resource_writes.size
    refute_includes out + err, "injected failure"
    refute_includes err, "retrying"
  end
end
