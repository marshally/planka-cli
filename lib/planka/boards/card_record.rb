module Planka
  module Boards
    # The card fields Planka accepts and returns: input limits, the validated
    # public projection, write confirmation, and read-back recovery.
    module CardRecord
      FIELDS = %w[id name description type boardId listId position createdAt updatedAt].freeze
      NAME_LIMIT = 1024
      DESCRIPTION_LIMIT = 1_048_576

      # Validates text the way Planka does: lengths count UTF-16 code units.
      def self.text?(value, limit)
        value.is_a?(String) && value.valid_encoding? && !value.empty? && value.encode("UTF-16LE").bytesize / 2 <= limit
      end

      def self.text!(field, value, limit)
        return value if text?(value, limit)

        raise ArgumentError, "#{field} must be nonempty and at most #{limit} characters"
      end

      def self.position!(position)
        return position if position.nil? || (position.is_a?(Numeric) && position.finite? && position >= 0)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def self.data(record)
        raise InvalidResponse, "Invalid card record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      # A card not yet created: only its board and list are known.
      def self.placeholder(destination)
        FIELDS.to_h { |field| [field, nil] }.merge("boardId" => destination.board_id, "listId" => destination.list_id)
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && record["name"].is_a?(String) &&
          (record["description"].nil? || record["description"].is_a?(String)) && record["type"].is_a?(String) &&
          Records.id?(record["boardId"]) && Records.id?(record["listId"]) &&
          (record["position"].nil? || (record["position"].is_a?(Numeric) && record["position"].finite?)) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end

      # The written card is the requested one; Planka may normalize finite
      # positions, so only their presence is checked.
      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || record["id"] == desired["id"]) &&
               %w[boardId listId name description type].all? { |field| record[field] == desired[field] } &&
               record["position"].nil? == desired["position"].nil?
          raise InvalidResponse, "Invalid card write response"
        end
      end

      def self.recovery(card)
        return { "action" => "readback-card", "resources" => [{ "type" => "card", "id" => card["id"] }] } if card["id"]

        { "action" => "readback-cards", "resources" => [{ "type" => "list", "id" => card["listId"] }] }
      end
    end
  end
end
