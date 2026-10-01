module Planka
  # Lists, creates and applies board labels. The board snapshot is the source of
  # truth for labels: a narrower endpoint has been seen to return an empty list
  # even when the board has labels. Creating and applying are reconciled against
  # that snapshot so a label is reused by exact name and an association is never
  # duplicated.
  #
  # client answers #board, #create_label and #add_card_label.
  class Labels
    POSITION_GAP = 65_536

    def initialize(client)
      @client = client
    end

    def list(board_id) = Array(@client.board(board_id)["labels"])

    def find_or_create(board_id:, name:, color:)
      labels = list(board_id)
      existing = labels.select { |label| label["name"] == name }
      raise Error, "ambiguous label name #{name}: #{existing.map { |l| l["id"] }.join(", ")}" if existing.size > 1
      return { "label" => existing.first, "created" => false } if existing.first

      label = @client.create_label(board_id, name:, color:, position: next_position(labels))
      { "label" => label, "created" => true }
    end

    # Applies a label, given its id or exact name, to a card. Safe to repeat: a
    # label already on the card is left as is and existing labels are preserved.
    def apply(card_id:, label:)
      response = @client.card(card_id)
      board_id = response.fetch("item")["boardId"]
      applied = Array(response.fetch("included")["cardLabels"])
      label_id = resolve(board_id, label)

      return { "cardId" => card_id, "labelId" => label_id, "created" => false } if applied.any? { |cl| cl["labelId"] == label_id }

      @client.add_card_label(card_id, label_id)
      { "cardId" => card_id, "labelId" => label_id, "created" => true }
    end

    private

    def resolve(board_id, label)
      board = @client.board(board_id)
      return label if Array(board["labels"]).any? { |existing| existing["id"] == label }

      Board.new(board).label_id(label)
    end

    def next_position(records) = (records.map { |record| record["position"].to_f }.max || 0) + POSITION_GAP
  end
end
