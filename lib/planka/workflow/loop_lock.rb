module Planka
  module Workflow
    # The Planka half of the work-next loop's global lock: a card the loop's
    # user has claimed that is still open and has no PR handed off yet. The
    # other half, an open agent-loop PR, is GitHub's to answer.
    #
    # comments answers #comments(card_id) with Planka's comment records.
    module LoopLock
      def self.report(client, base_url:, exclude_quarantine: false)
        boards = client.board_ids.map { |id| Board.new(Planka::Board.new(client.board(id), base_url: base_url)) }
        me = client.me.fetch("id")
        card = held(boards: boards, user_id: me, comments: client, exclude_quarantine: exclude_quarantine)
        return { "held" => false, "card" => nil } unless card

        claimed = card.claimed_at(me)
        { "held" => true, "card" => { "id" => card.id, "name" => card.name, "url" => card.url },
          "claimedAt" => claimed.iso8601, "ageSeconds" => (Time.now - claimed).to_i }
      end

      def self.held(boards:, user_id:, comments:, exclude_quarantine: false)
        boards.lazy.flat_map(&:cards).find do |card|
          card.claimed_by?(user_id) && card.open? && !(exclude_quarantine && card.quarantined?) && !Handoff.latest(comments.comments(card.id))&.pr_url
        end
      end
    end
  end
end
