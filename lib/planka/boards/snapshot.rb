module Planka
  module Boards
    # A machine-readable view of a board as GET /api/boards/:id returns it. The
    # records pass through unchanged, so identifiers, positions, list types,
    # descriptions and linked-task state are retained; cards gain a url and are
    # ordered by position so a caller sees the queue top to bottom.
    class Snapshot
      RECORD_TYPES = %w[lists cards labels cardLabels taskLists tasks cardMemberships].freeze

      def self.read(client, id, base_url:)
        { "boardId" => id }.merge(new(client.board(id), base_url: base_url, validate: true).to_h)
      end

      def self.validate!(included)
        unless included.is_a?(Hash) && RECORD_TYPES.all? { |key|
          records = included.fetch(key, [])
          records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) }
        }
          raise InvalidResponse, "Invalid board snapshot collections"
        end
        Array(included["cards"]).each do |card|
          position = card["position"]
          unless position.nil? || position.is_a?(Numeric) || position.is_a?(String)
            raise InvalidResponse, "Invalid card position"
          end
        end
      end

      def initialize(included, base_url: ENV.fetch("PLANKA_BASE_URL"), validate: false)
        self.class.validate!(included) if validate
        @included = included
        @base_url = base_url.sub(%r{/+\z}, "")
      end

      def to_h
        RECORD_TYPES.to_h { |type| [ type, records(type) ] }.merge("cards" => cards)
      end

      # Cards in one list, in position order, each carrying its url.
      def cards_in(list_id) = cards.select { |card| card["listId"] == list_id }

      def cards
        records("cards").sort_by { |card| card["position"].to_f }
          .map { |card| card.merge("url" => "#{@base_url}/cards/#{card["id"]}") }
      end

      private

      def records(type) = Array(@included[type])
    end
  end
end
