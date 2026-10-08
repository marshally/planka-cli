module Planka
  module Cards
    # Native comment fields and their public projection.
    module CommentRecord
      TEXT_LIMIT = 1_048_576
      FIELDS = %w[id cardId userId text createdAt updatedAt].freeze

      def self.text!(text)
        return text if Records.text?(text, TEXT_LIMIT) && !text.strip.empty?

        raise ArgumentError, "text must be nonempty and at most #{TEXT_LIMIT} UTF-16 units"
      end

      def self.placeholder(card_id) = FIELDS.to_h { |field| [field, nil] }.merge("cardId" => card_id)

      def self.returned_id(record, card_id)
        record["id"] if record.is_a?(Hash) && Records.id?(record["id"]) && record["cardId"] == card_id
      end

      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || desired["id"] == record["id"]) &&
               %w[cardId text].all? { |field| record[field] == desired[field] }
          raise InvalidResponse, "Invalid comment write response"
        end
      end

      def self.recovery(comment)
        resources = [{ "type" => "card", "id" => comment["cardId"] }]
        resources << { "type" => "comment", "id" => comment["id"] } if comment["id"]
        { "action" => comment["id"] ? "readback-comment" : "readback-comments", "resources" => resources }
      end

      def self.data(record)
        raise InvalidResponse, "Invalid comment record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.id?(record["cardId"]) &&
          (record["userId"].nil? || Records.id?(record["userId"])) && Records.text?(record["text"], TEXT_LIMIT) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
