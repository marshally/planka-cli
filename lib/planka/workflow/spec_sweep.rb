module Planka
  module Workflow
    # Spec cards whose work is finished: in in-progress, with at least one
    # ticket sharing their feature label, and every such ticket in a
    # closed-type list. The work-next loop moves them to done.
    module SpecSweep
      def self.complete(client, base_url:)
        moved = []
        client.board_ids.each do |board_id|
          board = Board.new(Planka::Board.new(client.board(board_id), base_url: base_url))
          finished(board).each do |spec|
            client.comment(spec.id, "Every ticket for this spec is closed, so planka-cli moves it to done.")
            client.move_card(spec.id, board.list_id("done"))
            moved << { "id" => spec.id, "name" => spec.name, "url" => spec.url }
          end
        end
        { "count" => moved.size, "moved" => moved }
      end

      def self.finished(board)
        board.cards.select do |card|
          next false if card.ticket? || !card.in_progress?

          tickets = card.features.flat_map { |label| board.cards_labelled(label) }.select(&:ticket?)
          tickets.any? && tickets.all?(&:closed?)
        end
      end
    end
  end
end
