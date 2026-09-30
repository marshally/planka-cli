module Planka
  # Spec cards whose work is finished: in in-progress, with at least one
  # ticket sharing their feature label, and every such ticket in a
  # closed-type list. The work-next loop moves them to done.
  module SpecSweep
    def self.finished(board)
      board.cards.select do |card|
        next false if card.ticket? || !card.in_progress?

        tickets = card.features.flat_map { |label| board.cards_labelled(label) }.select(&:ticket?)
        tickets.any? && tickets.all?(&:closed?)
      end
    end
  end
end
