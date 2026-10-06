module Planka
  class Labels
    # Reads the complete board label collection; label routes have no native GET.
    class Read
      FIELDS = %w[id boardId name color position createdAt updatedAt].freeze
      ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def self.read(client, reference = nil, board_id:, base_url:, name: nil, limit: nil) # rubocop:disable Lint/UnusedMethodArgument -- shared reader contract.
        data = []
        load_records(client, board_id, data)
        return Reference.resolve(data, reference, resource: "label") if reference

        collection(data, name, limit)
      rescue *ERRORS
        raise if reference

        raise CollectionFailure.new(data: collection(data, name, limit).data)
      end

      def self.load_records(client, board_id, data)
        board_records(client, board_id).each { |record| append_record(data, record, board_id) }
      end

      def self.board_records(client, board_id)
        records = client.board(board_id)["labels"]
        raise InvalidResponse, "Invalid board labels" unless records.is_a?(Array)

        records
      end

      def self.append_record(data, record, board_id)
        validate!(record, board_id: board_id)
        validate_unique!(data, record)
        data << project(record)
      end

      def self.validate_unique!(data, record)
        raise InvalidResponse, "Duplicate label ID" if data.any? { |existing| existing["id"] == record["id"] }
      end

      def self.project(record) = FIELDS.to_h { |field| [field, record[field]] }

      def self.validate!(record, board_id:)
        unless record.is_a?(Hash) && Records.id?(record["id"]) && record["boardId"] == board_id &&
               (record["name"].nil? || record["name"].is_a?(String)) &&
               record["color"].is_a?(String) && !record["color"].empty? &&
               record["position"].is_a?(Numeric) && record["position"].finite? && record["position"] >= 0 &&
               %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
          raise InvalidResponse, "Invalid label record"
        end
      end

      def self.collection(data, name, limit)
        matching = data.sort_by { |record| [record["position"], record["id"]] }
        matching = matching.select { |record| record["name"] == name } if name
        CollectionResult.new(data: limit ? matching.first(limit) : matching, complete: !limit || matching.size <= limit)
      end
      private_class_method :collection, :load_records, :board_records, :append_record, :validate_unique!
    end
  end
end
