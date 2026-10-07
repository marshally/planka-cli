module Planka
  module Boards
    # The list fields Planka accepts and returns: input limits, the validated
    # public projection, write confirmation, and read-back recovery.
    module ListRecord
      FIELDS = %w[id name type color boardId position createdAt updatedAt].freeze
      NAME_LIMIT = 128
      # Lists a caller may create or change; archive and trash are system lists.
      KANBAN_TYPES = ListScope::FINITE_TYPES
      COLORS = %w[berry-red pumpkin-orange lagoon-blue pink-tulip light-mud orange-peel bright-moss antique-blue
                  dark-granite turquoise-sea].freeze

      def self.name!(name)
        return name if Records.text?(name, NAME_LIMIT)

        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} characters"
      end

      def self.type!(type)
        return type if KANBAN_TYPES.include?(type)

        raise ArgumentError, "type must be one of #{KANBAN_TYPES.join(", ")}"
      end

      def self.position!(position)
        return position if position.nil? || Records.position?(position)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def self.data(record)
        raise InvalidResponse, "Invalid list record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      # A list not yet created: only its board is known.
      def self.placeholder(board_id) = FIELDS.to_h { |field| [field, nil] }.merge("boardId" => board_id)

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && (record["name"].nil? || record["name"].is_a?(String)) &&
          ListScope::TYPES.include?(record["type"]) && (record["color"].nil? || record["color"].is_a?(String)) &&
          Records.id?(record["boardId"]) && (record["position"].nil? || (record["position"].is_a?(Numeric) && record["position"].finite?)) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end

      # The written list is the requested one; Planka may normalize kanban
      # positions among the board's lists, so only their presence is checked.
      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || record["id"] == desired["id"]) &&
               %w[boardId name type color].all? { |field| record[field] == desired[field] } &&
               record["position"].nil? == desired["position"].nil?
          raise InvalidResponse, "Invalid list write response"
        end
      end

      def self.recovery(list)
        return { "action" => "readback-list", "resources" => [{ "type" => "list", "id" => list["id"] }] } if list["id"]

        { "action" => "readback-lists", "resources" => [{ "type" => "board", "id" => list["boardId"] }] }
      end
    end
  end
end
