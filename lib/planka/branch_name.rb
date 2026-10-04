module Planka
  # The branch a card is worked on: feature/<slug>-<ticket#>-<title> for a
  # card with a feature label, card/<title> without one. It also names the
  # checkout's Compose project and preview host with an optional prefix, a
  # DNS label of at most 63 characters, so it is cut on a word to fit.
  module BranchName
    def self.read(client, id, base_url:, prefix:)
      response = client.card(id)
      board_id = response.is_a?(Hash) && response["item"].is_a?(Hash) && response["item"]["boardId"]
      unless board_id.is_a?(String) && board_id.match?(/\A\d+\z/)
        raise InvalidResponse, "Invalid card board reference"
      end
      included = client.board(board_id)
      Snapshot.validate!(included)
      board = Board.new(included, base_url: base_url)
      card = board.card(id)
      valid_labels = included.fetch("cardLabels").all? do |relation|
        relation["cardId"].is_a?(String) && relation["labelId"].is_a?(String) &&
          (relation["cardId"] != id || board.label_name(relation["labelId"]).is_a?(String))
      end
      unless card.name.is_a?(String) && valid_labels
        raise InvalidResponse, "Invalid branch-name title or labels"
      end
      { "cardId" => id, "branch" => self.for(card, prefix: prefix) }
    rescue KeyError
      raise InvalidResponse, "Invalid branch-name board records"
    end

    def self.for(card, prefix: ENV.fetch("PLANKA_BRANCH_PREFIX", ""))
      max = max_length(prefix)

      feature = card.features.first&.delete_prefix("feature:")
      name = feature ? "feature/#{feature}-#{slug(card.name)}" : "card/#{slug(card.name)}"
      fit(name, max:)
    end

    def self.max_length(prefix)
      max = 63 - prefix.length
      raise Error, "branch prefix leaves too little space" if max < 8

      max
    end

    def self.slug(text) = text.downcase.gsub(/[^a-z0-9.]+/, "-").gsub(/\A-|-\z/, "")

    def self.fit(name, max:)
      return name if name.length <= max

      cut = name[0, max]
      boundary = cut.rindex("-")
      cut = cut[0, boundary] if boundary && name[max] != "-" && !cut.end_with?("-")
      cut.chomp("-")
    end
  end
end
