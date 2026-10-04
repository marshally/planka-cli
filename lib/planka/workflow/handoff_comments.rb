require "time"

module Planka
  module Workflow
    # Validated comment records for canonical handoff inspection.
    class HandoffComments
      def initialize(client)
        @client = client
      end

      def comments(id)
        records = @client.comments(id)
        unless records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) &&
          record["text"].is_a?(String) && record["createdAt"].is_a?(String) }
          raise InvalidResponse, "Invalid handoff comments"
        end
        records.each { |record| timestamp!(record["createdAt"]) }
        records
      end

      private

      def timestamp!(value)
        Time.iso8601(value)
      rescue ArgumentError
        raise InvalidResponse, "Invalid handoff comment timestamp"
      end
    end
  end
end
