require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class CardMembersCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD
  USER = "600000000000000001"

  def setup
    @server = FakePlanka.new
    @server.users << { "id" => USER, "name" => "Ada", "username" => "ada", "email" => "private@example.com" }
    @server.board_memberships << { "id" => "700000000000000001", "boardId" => FakePlanka::BOARD_ID, "userId" => USER, "role" => "editor" }
  end

  def teardown = @server.stop

  def planka(*args, env: {}, executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-password", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args, chdir: Dir.tmpdir)
  end

  def membership(user_id = USER, id = "800000000000000001")
    { "id" => id, "cardId" => CARD, "userId" => user_id, "createdAt" => "2026-10-05T00:00:00Z", "updatedAt" => nil }
  end

  def expected_member
    { "id" => USER, "name" => "Ada", "username" => "ada", "cardId" => CARD,
      "membershipId" => "800000000000000001", "createdAt" => "2026-10-05T00:00:00Z", "updatedAt" => nil }
  end

  def resource_writes
    @server.requests.select { |method, path, _| method != "GET" && !path.include?("access-tokens") }
  end

  def test_collection_reads_hydrate_identity_without_exposing_private_user_fields_or_writing
    @server.memberships << membership
    out, err, status = planka("get", "members", "--card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal({ "data" => [expected_member], "meta" => { "complete" => true }, "error" => nil }, JSON.parse(out))
    assert_empty resource_writes
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_individual_read_resolves_exact_board_member_name_and_user_url
    @server.memberships << membership
    ["Ada", "#{@server.base_url}/users/#{USER}"].each do |reference|
      out, err, status = planka("get", "members", reference, "--card", CARD, "-o", "json")
      assert status.success?, err
      assert_equal expected_member, JSON.parse(out)["data"]
      assert_equal({}, JSON.parse(out)["meta"])
    end
    assert_empty resource_writes
  end

  def test_filters_precede_limits_and_completeness_is_based_on_matching_members
    other = "600000000000000002"
    @server.users << { "id" => other, "name" => "Grace", "username" => nil }
    @server.memberships.concat([membership, membership(other, "800000000000000002")])
    out, err, status = planka("get", "members", "--card", CARD, "--name", "Grace", "--limit", "1", "-o", "json")
    assert status.success?, err
    assert_equal [other], JSON.parse(out)["data"].map { |member| member["id"] }
    assert_equal true, JSON.parse(out).dig("meta", "complete")
    out, err, status = planka("get", "member", "--card", CARD, "--limit", "1", "-o", "json")
    assert status.success?, err
    assert_equal [USER], JSON.parse(out)["data"].map { |member| member["id"] }
    assert_equal false, JSON.parse(out).dig("meta", "complete")
    out, err, status = planka("get", "members", "--card", CARD, "--limit", "1")
    assert status.success?, err
    assert_includes out, "Results truncated"
    assert_empty resource_writes
  end

  def test_add_assigns_only_the_specified_user_and_repeated_add_is_a_noop
    other = "600000000000000002"
    @server.users << { "id" => other, "name" => "Grace", "username" => nil }
    @server.memberships << membership(other, "800000000000000002")
    out, err, status = planka("add", "members", "Ada", "--card", CARD, "-o", "json")
    assert status.success?, err
    doc = JSON.parse(out)
    assert_equal true, doc.dig("meta", "changed")
    assert_equal true, doc.dig("data", "assigned")
    assert_equal USER, doc.dig("data", "id")
    assert_equal [["POST", "/api/cards/#{CARD}/card-memberships", { "userId" => USER }]],
                 resource_writes.map { |method, path, body| [method, path, JSON.parse(body)] }
    out, err, status = planka("add", "member", USER, "--card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("meta", "changed")
    assert_equal 1, resource_writes.size
    read, err, status = planka("describe", "card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal [other, USER], JSON.parse(read).dig("data", "members")
    assert_equal FakePlanka::LIST_READY, JSON.parse(read).dig("data", "listId")
  end

  def test_remove_uses_the_card_user_pair_and_absent_assignment_is_a_noop
    @server.memberships << membership
    out, err, status = planka("remove", "member", USER, "--card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal true, JSON.parse(out).dig("meta", "changed")
    assert_equal false, JSON.parse(out).dig("data", "assigned")
    assert_equal "800000000000000001", JSON.parse(out).dig("data", "membershipId")
    assert_equal [["DELETE", "/api/cards/#{CARD}/card-memberships/userId:#{USER}", ""]], resource_writes
    out, err, status = planka("remove", "members", "Ada", "--card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal false, JSON.parse(out).dig("meta", "changed")
    assert_nil JSON.parse(out).dig("data", "membershipId")
    assert_equal 1, resource_writes.size
    out, err, status = planka("get", "members", "--card", CARD, "-o", "json")
    assert status.success?, err
    assert_equal [], JSON.parse(out)["data"]
  end

  def test_unknown_writes_preserve_identity_and_require_readback_without_retry
    ["add", "remove"].each do |verb|
      @server.requests.clear
      @server.memberships.clear
      @server.memberships << membership if verb == "remove"
      method = verb == "add" ? "POST" : "DELETE"
      @server.inject(method, %r{card-memberships}, :apply_then_drop)
      out, err, status = planka(verb, "member", USER, "--card", CARD, "-o", "json")
      assert_equal 1, status.exitstatus, err
      doc = JSON.parse(out)
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_equal USER, doc.dig("data", "id")
      assert_nil doc.dig("data", "assigned")
      assert_equal "readback-membership", doc.dig("error", "recovery", "action")
      assert_equal 1, resource_writes.size
      read, err, status = planka("get", "members", "--card", CARD, "-o", "json")
      assert status.success?, err
      assert_equal(verb == "add" ? [USER] : [], JSON.parse(read)["data"].map { |member| member["id"] })
      retry_out, err, status = planka(verb, "member", USER, "--card", CARD, "-o", "json")
      assert status.success?, err
      assert_equal false, JSON.parse(retry_out).dig("meta", "changed")
      assert_equal 1, resource_writes.size
    end
  end

  def test_card_name_uses_known_board_scope_and_explicit_mismatches_fail_without_writes
    @server.memberships << membership
    out, err, status = planka("get", "member", "Ada", "--card", "Spec: Work-next refinement",
                              "--board", @server.board_id, "-o", "json")
    assert status.success?, err
    assert_equal expected_member, JSON.parse(out)["data"]
    out, err, status = planka("add", "member", USER, "--card", CARD, "--board", "999", "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_empty resource_writes
    out, err, status = planka("get", "members", "--card", CARD, "-o", "json", env: { "PLANKA_BOARD_ID" => "999" })
    assert status.success?, err
    assert_equal [expected_member], JSON.parse(out)["data"]
  end

  def test_malformed_collections_fail_safely_and_preserve_known_members
    @server.memberships.concat([membership, { "id" => "unsafe", "cardId" => CARD, "userId" => USER }])
    out, err, status = planka("get", "members", "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal [expected_member], JSON.parse(out)["data"]
    assert_equal false, JSON.parse(out).dig("meta", "complete")
    @server.inject("GET", %r{/cards/#{CARD}$}, { "item" => @server.find_card(CARD), "included" => [] })
    out, err, status = planka("get", "members", "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal "api_error", JSON.parse(out).dig("error", "code")
    assert_equal [], JSON.parse(out)["data"]
    refute_match(/TypeError|NoMethodError|KeyError/, out + err)
    assert_empty resource_writes
  end

  def test_partial_collections_still_apply_filters_order_and_limits
    @server.memberships.concat([membership, { "id" => "unsafe", "cardId" => CARD }])
    out, err, status = planka("get", "members", "--card", CARD, "--name", "Grace", "--limit", "1", "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal [], JSON.parse(out)["data"]
    assert_equal false, JSON.parse(out).dig("meta", "complete")
    @server.memberships.replace([membership(USER, "803"), membership("602", "802"), { "id" => "unsafe", "cardId" => CARD }])
    @server.users << { "id" => "602", "name" => "Grace", "username" => nil }
    out, err, status = planka("get", "members", "--card", CARD, "--limit", "1", "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal ["602"], JSON.parse(out)["data"].map { |member| member["id"] }
    assert_equal false, JSON.parse(out).dig("meta", "complete")
  end

  def test_root_group_and_leaf_help_advertise_implemented_member_commands_offline
    [["--help"], ["get", "--help"], ["add", "--help"], ["remove", "--help"],
     ["get", "members", "--help"], ["add", "member", "--help"], ["remove", "members", "--help"]].each do |args|
      out, err, status = planka(*args, env: { "PLANKA_AGENT_PASSWORD" => nil })
      assert status.success?, err
      assert_includes out, "member"
      assert_includes out, "add member USER --card CARD" if args == ["--help"]
      refute_includes out, "usage: planka get members" if args.first != "get"
    end
    assert_empty @server.requests
  end

  def test_invalid_inputs_and_configuration_fail_before_authentication
    [["get", "members", "--card", CARD, "--name", ""],
     ["get", "members", "--card", CARD, "--limit", "0"],
     ["get", "members", "--card", CARD, "--limit", "1.5"],
     ["get", "member", USER, "--card", CARD, "--limit", "1"],
     ["get", "members", "--card", CARD, "--name", "Ada", "--name", "Grace"],
     ["get", "members", "--card", CARD, "--member", USER],
     ["add", "member", USER], ["remove", "member", "--card", CARD],
     ["add", "member", USER, "--card", CARD, "--card", "999"],
     ["add", "member", "https://other.example/users/#{USER}", "--card", CARD],
     ["get", "members", "--card", "https://other.example/cards/#{CARD}"],
     ["add", "member", "Ada", "--card", "Spec: Work-next refinement"]].each do |args|
      out, err, status = planka(*args, "-o", "json")
      assert_equal 2, status.exitstatus, out + err
      assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    end
    out, err, status = planka("add", "member", USER, "--card", CARD, "-o", "json", env: { "PLANKA_AGENT_PASSWORD" => nil })
    assert_equal 1, status.exitstatus, err
    assert_equal "configuration_error", JSON.parse(out).dig("error", "code")
    assert_empty @server.requests
  end

  def test_rejected_and_malformed_writes_preserve_the_primary_outcome_and_cleanup
    ["add", "remove"].each do |verb|
      @server.memberships.clear
      @server.memberships << membership if verb == "remove"
      method = verb == "add" ? "POST" : "DELETE"
      @server.inject(method, %r{card-memberships}, 403)
      @server.inject("DELETE", %r{access-tokens/me$}, 403)
      out, err, status = planka(verb, "member", USER, "--card", CARD, "-o", "json")
      assert_equal 1, status.exitstatus
      assert_equal "authorization_error", JSON.parse(out).dig("error", "code")
      assert_equal false, JSON.parse(out).dig("meta", "changed")
      assert_equal USER, JSON.parse(out).dig("data", "id")
      assert_includes err, "session cleanup failed"
      refute_includes out + err, "private upstream body"
      @server.inject(method, %r{card-memberships}, { "item" => { "id" => "999", "cardId" => "999", "userId" => USER } })
      out, err, status = planka(verb, "member", USER, "--card", CARD, "-o", "json")
      assert_equal 1, status.exitstatus, err
      assert_equal "unknown_outcome", JSON.parse(out).dig("error", "code")
      assert_nil JSON.parse(out).dig("meta", "changed")
    end
  end

  def test_scope_ambiguity_missing_users_and_unassigned_reads_reject_without_writes
    out, err, status = planka("get", "member", USER, "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal "not_found", JSON.parse(out).dig("error", "code")
    @server.users << { "id" => "602", "name" => "Ada", "username" => nil }
    @server.board_memberships << { "id" => "702", "boardId" => @server.board_id, "userId" => "602" }
    out, err, status = planka("add", "member", "Ada", "--card", CARD, "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_includes err, USER
    assert_includes err, "602"
    out, err, status = planka("add", "member", "999", "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal "not_found", JSON.parse(out).dig("error", "code")
    @server.cards << @server.find_card(CARD).merge("id" => "403")
    out, err, status = planka("get", "members", "--card", "Spec: Work-next refinement", "--board", @server.board_id, "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_includes err, CARD
    assert_includes err, "403"
    assert_empty resource_writes
  end

  def test_api_failures_keep_categories_and_collection_completeness
    [["POST", %r{access-tokens$}, 401, "authentication_error"],
     ["GET", %r{/cards/#{CARD}$}, 404, "not_found"],
     ["GET", %r{boards/.+$}, 403, "authorization_error"]].each do |method, path, code, category|
      @server.inject(method, path, code)
      out, err, status = planka("get", "members", "--card", CARD, "-o", "json")
      assert_equal 1, status.exitstatus, err
      assert_equal category, JSON.parse(out).dig("error", "code")
      assert_equal false, JSON.parse(out).dig("meta", "complete")
      refute_includes out + err, "private upstream body"
    end
    assert_empty resource_writes
  end

  def test_success_survives_cleanup_failure_and_human_mutations_report_assignment
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    out, err, status = planka("add", "member", USER, "--card", CARD)
    assert status.success?, err
    assert_includes out, "assigned: true"
    assert_includes err, "operation result is unchanged"
  end
end
