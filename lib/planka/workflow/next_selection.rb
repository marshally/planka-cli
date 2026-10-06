module Planka
  module Workflow
    # Canonical queue inspection shares the legacy selector and report rules.
    module NextSelection
      def self.read(client, base_url:, board_id:, labels:)
        included = client.board(board_id)
        board = QueueSnapshot.board(included, base_url: base_url)
        mode = labels.find { |label| label.start_with?("feature:", "effort:") }
        NextCard.for(mode, board: FilteredBoard.new(board, labels), comments: HandoffComments.new(client), pull_requests: PullRequestLookup)
      rescue KeyError
        raise InvalidResponse, "Invalid workflow-next board records"
      end

      # Narrow selection without removing the original board's blocker lookup.
      class FilteredBoard
        def initialize(board, labels)
          @board, @labels = board, labels
        end

        def cards = matching(@board.cards)

        def cards_labelled(name)
          return [] unless @board.cards.any? { |card| card.labelled?(name) }

          matching(@board.cards_labelled(name))
        end

        private

        def matching(cards) = cards.select { |card| @labels.all? { |label| card.labelled?(label) } }
      end
    end
  end
end
