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
  def test_an_uncertain_add_is_not_retried
    @server.inject("POST", %r{card-labels$}, :apply_then_drop)
    out, err, status = planka("add", "label", "enhancement", "--card", CARD, "-o", "json")
    assert_equal 1, status.exitstatus, err
    assert_equal "unknown_outcome", JSON.parse(out).dig("error", "code")
    assert_nil JSON.parse(out).dig("meta", "changed")
    assert_equal 1, @server.counts("POST", %r{card-labels$})
  end

  def test_add_and_remove_are_generic_idempotent_relationships
    %w[add add remove remove].zip([true, false, true, false]).each do |verb, changed|
      out, err, status = planka(verb, "label", "enhancement", "--card", CARD, "-o", "json")
      assert status.success?, err
      assert_equal changed, JSON.parse(out).dig("meta", "changed")
    end
    assert_empty @server.card_labels
  end
end
