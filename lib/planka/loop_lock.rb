module Planka
  # The Planka half of the work-next loop's global lock: a card the loop's
  # user has claimed that is still open and has no PR handed off yet. The
  # other half, an open agent-loop PR, is GitHub's to answer.
  #
  # comments answers #comments(card_id) with Planka's comment records.
  module LoopLock
    def self.held(boards:, user_id:, comments:)
      boards.lazy.flat_map(&:cards).find do |card|
        card.claimed_by?(user_id) && card.open? && !Handoff.latest(comments.comments(card.id))&.pr_url
      end
    end
  end
end
