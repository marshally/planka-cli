require_relative "planka_test_helper"

class Planka::LoopLockTest < Minitest::Test
  include PlankaTestHelper

  BOT = "bot"

  Comments = Struct.new(:by_card) do
    def comments(card_id) = by_card.fetch(card_id, [])
  end

  def held(comments: {}) = Planka::Workflow::LoopLock.held(boards: [ board ], user_id: BOT, comments: Comments.new(comments))

  def claim_as_bot(id) = payload["cardMemberships"] << { "cardId" => id, "userId" => BOT }

  def handoff = [ { "createdAt" => "2026-09-29T10:00:00Z", "text" => "Branch: b\nPR: https://github.com/x/y/pull/1" } ]

  def test_nothing_claimed_by_the_bot_is_free
    claim(card_id("Contract edits"))

    assert_nil held
  end

  def test_a_bot_claim_without_a_pr_holds_the_lock
    claim_as_bot(card_id("Contract edits"))
    move(card_id("Contract edits"), "in-progress")

    assert_equal card_id("Contract edits"), held.id
  end

  def test_a_bot_claim_whose_pr_is_handed_off_does_not
    claim_as_bot(card_id("Contract edits"))

    assert_nil held(comments: { card_id("Contract edits") => handoff })
  end

  def test_a_closed_bot_claim_does_not
    claim_as_bot(card_id("Contract edits"))
    close(card_id("Contract edits"))

    assert_nil held
  end

  def test_the_card_knows_when_the_bot_claimed_it
    payload["cardMemberships"] << { "cardId" => card_id("Contract edits"), "userId" => BOT, "createdAt" => "2026-09-29T15:00:00.000Z" }

    assert_equal Time.utc(2026, 9, 29, 15), held.claimed_at(BOT)
  end
end
