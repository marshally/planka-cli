module Planka
  module Projects
    # The concise board projection, independent of snapshot-related records.
    module BoardRecord
      FIELDS = %w[id projectId name position createdAt updatedAt].freeze
      NAME_LIMIT = 128

      def self.name!(name)
        return name if Records.text?(name, NAME_LIMIT) && !name.strip.empty?

        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} UTF-16 units"
      end

      def self.position!(position)
        return position if Records.position?(position)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def self.placeholder(project_id) = (FIELDS + ["url"]).to_h { |field| [field, nil] }.merge("projectId" => project_id)

      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || record["id"] == desired["id"]) &&
               %w[projectId name].all? { |field| record[field] == desired[field] }
          raise InvalidResponse, "Invalid board write response"
        end
      end

      def self.recovery(board)
        resources = [{ "type" => "project", "id" => board["projectId"] }]
        resources << { "type" => "board", "id" => board["id"] } if board["id"]
        { "action" => board["id"] ? "readback-board" : "readback-boards", "resources" => resources }
      end

      def self.created_id(record, existing_ids)
        record["id"] if record.is_a?(Hash) && Records.id?(record["id"]) && !existing_ids.include?(record["id"])
      end

      def self.data(record, base_url:)
        raise InvalidResponse, "Invalid board record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }.merge("url" => "#{base_url}/boards/#{record["id"]}")
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.id?(record["projectId"]) &&
          record["name"].is_a?(String) && Records.position?(record["position"]) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
