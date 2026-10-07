module Planka
  module Boards
    # The list fields Planka accepts and returns: input limits, the validated
    # public projection, write confirmation, and read-back recovery.
    module ListRecord
      FIELDS = %w[id name type color boardId position createdAt updatedAt].freeze

      def self.data(record)
        raise InvalidResponse, "Invalid list record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && (record["name"].nil? || record["name"].is_a?(String)) &&
          ListScope::TYPES.include?(record["type"]) && (record["color"].nil? || record["color"].is_a?(String)) &&
          Records.id?(record["boardId"]) && (record["position"].nil? || (record["position"].is_a?(Numeric) && record["position"].finite?)) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
