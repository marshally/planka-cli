require_relative "planka_test_helper"

class Planka::BranchNameTest < Minitest::Test
  include PlankaTestHelper

  def branch(name, features: [])
    card = Struct.new(:name, :features).new(name, features)
    Planka::Workflow::BranchName.for(card, prefix: "lucenta-")
  end

  def test_a_feature_ticket_names_its_feature_number_and_title
    assert_equal "feature/tracer-1.1-a-monitor-sees-lucenta-is-up",
                 branch("1.1 A monitor sees lucenta is up", features: ["feature:tracer"])
  end

  def test_punctuation_becomes_single_hyphens
    assert_equal "feature/work-next-w2-the-top-of-ready-for-agent-is-the",
                 branch("W2 The top of ready-for-agent is the priority!", features: ["feature:work-next"])
  end

  def test_a_card_without_a_feature_is_named_by_its_title
    assert_equal "card/fix-the-login-redirect", branch("Fix the login redirect")
  end

  def test_the_name_fits_a_dns_label_after_the_lucenta_prefix_and_ends_on_a_whole_word
    name = branch("1.2 An account signs in; the first admin exists", features: ["feature:tracer"])

    assert_equal "feature/tracer-1.2-an-account-signs-in-the-first-admin", name
    assert_operator "lucenta-#{name}".length, :<=, 63
  end

  def test_a_fixture_card_takes_its_feature_from_its_labels
    assert_equal "feature/workspaces-contract-edits-by-direct-request",
                 Planka::Workflow::BranchName.for(board.card(card_id("Contract edits")), prefix: "lucenta-")
  end
end
