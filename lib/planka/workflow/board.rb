module Planka
  module Workflow
    # Workflow card interpretations over a general Planka board snapshot.
    class Board
      def initialize(board)
        @board = board
        @cards = board.cards.to_h { |card| [card.id, Card.new(self, card)] }
      end

      def card(id) = @cards.fetch(id)
      def cards = @cards.values
      def cards_labelled(name) = @board.cards_labelled(name).map { |card| self.card(card.id) }
      def list_id(name) = @board.list_id(name)
      def label_name(id) = @board.label_name(id)
    end
  end
end
