require_relative "planka_test_helper"

class Planka::SpecSweepTest < Minitest::Test
  include PlankaTestHelper

  def finished = Planka::Workflow::SpecSweep.finished(board).map(&:id)

  def test_a_spec_in_progress_whose_tickets_are_all_closed_is_finished
    move(card_id("Spec:"), "in-progress")
    close(*ticket_ids)

    assert_equal [ card_id("Spec:") ], finished
  end

  def test_one_open_ticket_keeps_it_open
    move(card_id("Spec:"), "in-progress")
    close(*ticket_ids.drop(1))

    assert_empty finished
  end

  def test_a_spec_with_no_tickets_is_left_alone
    add_label("feature:empty", card_id("Spec:"))
    payload["cardLabels"].reject! { |cl| cl["labelId"] != "label-feature:empty" && cl["cardId"] == card_id("Spec:") }
    move(card_id("Spec:"), "in-progress")

    assert_empty finished
  end

  def test_a_spec_that_isnt_in_progress_is_left_alone
    close(*ticket_ids)

    assert_empty finished
  end
end
