module Planka
  # A card the picked ticket is blocked by, with where its work lives: the
  # handoff comment it left and the state of that PR.
  Blocker = Data.define(:card, :handoff, :pr) do
    # comments answers #comments(card_id); pull_requests answers #find(url).
    def self.for(card, comments:, pull_requests:)
      handoff = Handoff.latest(comments.comments(card.id))
      new(card:, handoff:, pr: handoff&.pr_url && pull_requests.find(handoff.pr_url))
    end

    # The branch to stack a ticket on: main once every blocker has merged, the
    # one unmerged blocker's branch, or AMBIGUOUS when that can't be decided.
    def self.parent_branch(blockers)
      unrecorded = blockers.reject(&:recorded?)
      return "AMBIGUOUS: no Branch: comment on #{unrecorded.map { |b| b.card.name }.join(", ")}" if unrecorded.any?

      unmerged = blockers.reject(&:merged?)
      return "AMBIGUOUS: unmerged blockers #{unmerged.map(&:branch).join(", ")}" if unmerged.size > 1

      unmerged.first&.branch || "main"
    end

    def recorded? = !handoff.nil?
    def merged? = pr&.merged? || false
    def branch = pr&.head || handoff&.branch

    def to_s
      return "- #{card}: no Branch: comment" unless recorded?

      "- #{card}: branch #{handoff.branch}, PR #{handoff.pr_url || "none"} (#{pr&.state&.downcase || "unknown"})"
    end
  end
end
