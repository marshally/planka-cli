module Planka
  module Boards
    # Moves a card to one list on its own board. Reading the card also verifies
    # the destination, so the move's desired state needs no further reads.
    class CardMove < Resource
      def initialize(client, list:, board_id: nil)
        super(client)
        raise ArgumentError, "list must be a nonempty reference" unless list.is_a?(String) && !list.strip.empty?

        @list, @board_id = list, board_id
      end

      # Appends unless positioned; the current list without a position is
      # already satisfied. Only list and position change.
      def move(reference, position: nil) = update(reference, position: position)

      private

      def update_attributes(position:) = { "position" => CardRecord.position!(position) }

      def read_record(reference)
        card = CardScope.new(client, board_id: @board_id).card(reference)
        destination = CardScope.new(client, board_id: card["boardId"], parent: "the card's board").destination(@list, excluding: card["id"])
        CardScope::Observation.new(card: card, destination: destination)
      end

      def record_data(known) = known.card

      def updated_data(known, attributes)
        card, destination, requested = known.card, known.destination, attributes["position"]
        settled = requested.nil? && destination.finite && card["listId"] == destination.list_id
        card.merge("listId" => destination.list_id, "position" => settled ? card["position"] : destination.position(requested))
      end

      # A list change always carries its position; a reposition sends only position.
      def update_record(known, desired)
        request = { position: desired["position"] }
        request[:listId] = desired["listId"] unless desired["listId"] == known.card["listId"]
        client.update_card(known.card["id"], **request)
      end

      def validate_record!(record, desired) = CardRecord.confirm!(record, desired)
      def confirmed_data(record, _desired) = CardRecord.data(record)
      def recovery(known) = CardRecord.recovery(known.card)
    end
  end
end
