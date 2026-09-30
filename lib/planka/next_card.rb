module Planka
  # Picks the next card to work. With no label it picks the top ticket in
  # ready-for-agent, whose order the human sets as priority. A feature label
  # (feature:<slug>) picks the feature's next ticket in creation order and the
  # branch to stack it on; an effort label (effort:<slug>) runs the wayfinder
  # frontier query. Spec cards, which carry no Acceptance criteria list, are
  # never picked.
  #
  # comments answers #comments(card_id) with Planka's comment records;
  # pull_requests answers #find(url) with a PullRequest or nil.
  module NextCard
    def self.for(label, board:, comments:, pull_requests:)
      if label.nil?
        PriorityTicket.new(board, comments:, pull_requests:)
      elsif label.start_with?("effort:")
        Frontier.new(board.cards_labelled(label))
      else
        FeatureTicket.new(board.cards_labelled(label), comments:, pull_requests:)
      end.report
    end

    # Tickets go in creation order, the order /to-tickets publishes them in;
    # card positions don't follow it.
    class FeatureTicket
      def initialize(cards, comments:, pull_requests:)
        @spec, @tickets = cards.partition { |card| !card.ticket? }
        @tickets.sort_by!(&:created_at)
        @comments = comments
        @pull_requests = pull_requests
      end

      def report
        pick = @tickets.find(&:takeable?) or return Waiting.new(@tickets.select(&:ready?))

        Pick.new(card: pick, spec: @spec, nn: @tickets.index(pick) + 1, blockers: pick.blockers.map { |card| blocker(card) })
      end

      private

      def blocker(card) = Blocker.for(card, comments: @comments, pull_requests: @pull_requests)
    end

    # The top takeable ticket in ready-for-agent by position: the human orders
    # the list, top to bottom, by priority.
    class PriorityTicket
      def initialize(board, comments:, pull_requests:)
        @board = board
        @tickets = board.cards.select { |card| card.ticket? && card.ready? }.sort_by(&:position)
        @comments = comments
        @pull_requests = pull_requests
      end

      def report
        pick = @tickets.find(&:takeable?) or return Waiting.new(@tickets)

        Pick.new(card: pick, spec: specs(pick), nn: nil, blockers: pick.blockers.map { |card| blocker(card) })
      end

      private

      def specs(ticket) = ticket.features.flat_map { |label| @board.cards_labelled(label).reject(&:ticket?) }

      def blocker(card) = Blocker.for(card, comments: @comments, pull_requests: @pull_requests)
    end

    Pick = Data.define(:card, :spec, :nn, :blockers) do
      def to_s
        [
          "card: #{card}",
          "spec: #{spec.empty? ? "none" : spec.join(", ")}",
          *(format("nn: %02d", nn) if nn),
          "blockers:#{" none" if blockers.empty?}",
          *blockers,
          "parent: #{Blocker.parent_branch(blockers)}"
        ].join("\n")
      end
    end

    Waiting = Data.define(:cards) do
      def to_s = [ "none:", *cards.map { |card| "- #{card}: #{holds(card)}" } ].join("\n")

      private

      def holds(card)
        blocked_by = card.open_blockers.map(&:name)
        [ ("claimed" if card.claimed?), ("blocked by #{blocked_by.join(", ")}" if blocked_by.any?) ].compact.join("; ")
      end
    end

    # The wayfinder frontier, lowest position first, as the tracker doc orders it.
    class Frontier
      MAP_LABEL = "wayfinder:map"

      def initialize(cards)
        @maps, children = cards.partition { |card| card.labelled?(MAP_LABEL) }
        @frontier = children.select(&:takeable?).sort_by(&:position)
      end

      def report = FrontierReport.new(maps: @maps, frontier: @frontier)
    end

    FrontierReport = Data.define(:maps, :frontier) do
      def to_s
        [
          "card: #{frontier.first || "none"}",
          "map: #{maps.empty? ? "none" : maps.join(", ")}",
          "frontier:#{" none" if frontier.empty?}",
          *frontier.map { |card| "- #{card}" }
        ].join("\n")
      end
    end
  end
end
