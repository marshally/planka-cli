require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"
require_relative "../../../lib/planka"

class Planka::LabelRelationshipCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD
  def setup = @server = FakePlanka.new
  def teardown = @server.stop
  def planka(*args)
    env = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "fixture" }
    Open3.capture3(env, RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
  end
  def test_unknown_writes_require_readback_without_retry
    [ [ "add", "POST", %r{card-labels$} ], [ "remove", "DELETE", %r{card-labels/} ] ].each do |verb, method, path|
      planka("add", "label", "enhancement", "--card", CARD) if verb == "remove"
      @server.inject(method, path, :apply_then_drop)
      out, err, status = planka(verb, "label", "enhancement", "--card", CARD, "-o", "json")
      doc = JSON.parse(out)
      assert_equal 1, status.exitstatus, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_nil doc.dig("data", "present")
      assert_equal "readback-card-labels", doc.dig("error", "recovery", "action")
      assert_equal 1, @server.counts(method, path)
    end
  end

  def test_a_rejected_write_reports_the_unchanged_relationship
    @server.inject("POST", %r{card-labels$}, 403)
    out, err, status = planka("add", "label", "enhancement", "--card", CARD, "-o", "json")
    doc = JSON.parse(out)
    assert_equal 1, status.exitstatus, err
    assert_equal "authorization_error", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_equal({ "cardId" => CARD, "labelId" => FakePlanka::LABEL_ENHANCEMENT, "present" => false }, doc["data"])
  end

  def test_an_unknown_label_is_a_not_found_reference
    out, err, status = planka("add", "label", "no-such-label", "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal({ "code" => "not_found", "message" => "Label not found on the specified board" }, JSON.parse(out)["error"])
    assert_equal 0, @server.counts("POST", %r{card-labels$})
  end

  def test_an_ambiguous_label_name_lists_candidates_as_invalid_input
    @server.add_label("enhancement")
    out, err, status = planka("add", "label", "enhancement", "--card", CARD, "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_equal "invalid_input", JSON.parse(out).dig("error", "code")
    assert_match(/\AAmbiguous label name; candidate IDs: \d+, \d+\z/, JSON.parse(out).dig("error", "message"))
  end

  def test_add_and_remove_are_generic_idempotent_relationships
    %w[add add remove remove].zip([true, false, true, false]).each do |verb, changed|
      out, err, status = planka(verb, "label", "enhancement", "--card", CARD, "-o", "json")
      assert status.success?, err
      assert_equal changed, JSON.parse(out).dig("meta", "changed")
    end
    assert_empty @server.card_labels
  end

  def test_a_card_name_resolves_within_the_asserted_board
    name = @server.find_card(CARD).fetch("name")
    out, err, status = planka("add", "label", "enhancement", "--card", name, "--board", @server.board_id, "-o", "json")
    assert status.success?, err
    assert_equal CARD, JSON.parse(out).dig("data", "cardId")
    out, err, status = planka("add", "label", "enhancement", "--card", name, "-o", "json")
    assert_equal 2, status.exitstatus
    assert_equal "Card names require --board or PLANKA_BOARD_ID", JSON.parse(out).dig("error", "message")
  end

  def test_card_scope_is_required_like_member_commands
    out, err, status = planka("remove", "label", "enhancement", "-o", "json")
    assert_equal 2, status.exitstatus, err
    assert_equal({ "code" => "invalid_input", "message" => "Exactly one --card is required" }, JSON.parse(out)["error"])
    assert_empty @server.requests
  end

  def test_human_output_reports_the_relationship
    out, err, status = planka("add", "label", "enhancement", "--card", CARD)
    assert status.success?, err
    assert_equal "Label #{FakePlanka::LABEL_ENHANCEMENT} on card #{CARD}\npresent: true\n", out
  end

  def test_group_help_lists_label_and_member_relationships_offline
    %w[add remove].each do |verb|
      out, err, status = planka(verb, "--help")
      assert status.success?, err
      assert_includes out, "usage: planka #{verb} <resource> REF --card CARD [flags]"
      assert_match(/^  label LABEL --card CARD  /, out)
      assert_match(/^  member USER --card CARD  /, out)
    end
    out, = planka("--help")
    assert_match(/^  add label LABEL --card CARD  /, out)
    assert_empty @server.requests
  end

  def test_a_malformed_write_response_is_an_unknown_outcome
    @server.inject("POST", %r{card-labels$}, { "item" => { "cardId" => "999", "labelId" => FakePlanka::LABEL_ENHANCEMENT } })
    out, err, status = planka("add", "label", "enhancement", "--card", CARD, "-o", "json")
    doc = JSON.parse(out)
    assert_equal 1, status.exitstatus, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_equal "readback-card-labels", doc.dig("error", "recovery", "action")
  end

  def test_leaf_help_needs_no_credentials_or_network
    [["add", "label", "--help"], ["remove", "labels", "--help"]].each do |args|
      out, err, status = Open3.capture3({ "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil },
        RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
      assert status.success?, err
      assert_includes out, "usage: planka #{args.first} label LABEL --card CARD [--board BOARD] [-o human|json]"
    end
    assert_empty @server.requests
  end
end
