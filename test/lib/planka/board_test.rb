require_relative "planka_test_helper"

class Planka::BoardTest < Minitest::Test
  include PlankaTestHelper

  def test_cards_labelled_returns_the_cards_carrying_the_label
    names = board.cards_labelled("feature:workspaces").map(&:name)

    assert_equal 10, names.size
    assert_includes names, "Spec: Workspaces, membership and roles (Plan 3)"
  end

  def test_cards_labelled_raises_for_an_unknown_label
    error = assert_raises(Planka::Error) { board.cards_labelled("feature:nope") }

    assert_equal "no label feature:nope", error.message
  end

  def test_a_ticket_has_acceptance_criteria_and_the_spec_does_not
    assert board.card(card_id("Contract edits")).ticket?
    refute board.card(card_id("Spec:")).ticket?
  end

  def test_the_first_ticket_is_takeable
    assert board.card(card_id("Contract edits")).takeable?
  end

  def test_a_ticket_with_an_open_blocker_is_not_takeable
    card = board.card(card_id("Create a workspace"))

    refute card.takeable?
    assert_equal(["Contract edits"], card.open_blockers.map { |b| b.name[0, 14] })
  end

  def test_closing_the_blocker_makes_the_ticket_takeable
    close(card_id("Contract edits"))

    assert board.card(card_id("Create a workspace")).takeable?
  end

  def test_a_claimed_card_is_not_takeable
    claim(card_id("Contract edits"))
    card = board.card(card_id("Contract edits"))

    assert card.claimed?
    refute card.takeable?
  end

  def test_a_card_outside_ready_for_agent_is_not_takeable
    move(card_id("Contract edits"), "in-progress")

    refute board.card(card_id("Contract edits")).takeable?
  end

  def test_blockers_lists_every_linked_card_whether_open_or_closed
    id = card_id("Adding members")
    close(card_id("Documents inside"))

    assert_equal [card_id("Documents inside")], board.card(id).blockers.map(&:id)
    assert_empty board.card(id).open_blockers
  end

  def test_a_core_card_answers_from_its_own_related_records
    card = Planka::Board.new(payload, base_url: "https://planka.test/").card(card_id("Contract edits"))

    assert_equal "ready-for-agent", card.list_name
    assert_includes card.label_names, "feature:workspaces"
    assert_includes card.task_list_names, "Acceptance criteria"
    assert_equal "https://planka.test/cards/#{card.id}", card.url
  end

  def test_a_card_renders_as_its_name_and_link
    assert_equal "Transferring ownership (https://planka.home.yountlabs.com/cards/#{card_id("Transferring")})",
                 board.card(card_id("Transferring")).to_s
  end

  def test_unticked_criteria_are_the_open_tasks_in_the_acceptance_criteria_list
    card = card_id("Contract edits")
    criteria = payload["taskLists"].find { |tl| tl["cardId"] == card && tl["name"] == "Acceptance criteria" }.fetch("id")
    tasks = payload["tasks"].select { |t| t["taskListId"] == criteria }
    tasks.first["isCompleted"] = true

    assert_equal tasks.drop(1).map { |t| t["name"] }, board.card(card).unticked_criteria
    refute_empty board.card(card).unticked_criteria
  end
end
