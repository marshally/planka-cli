module Planka
  class Projects < Resource
    # The validated public project fields; URLs come from the selected instance.
    module Record
      FIELDS = %w[id name description ownerProjectManagerId createdAt updatedAt].freeze
      NAME_LIMIT = 128
      DESCRIPTION_LIMIT = 1024

      def self.data(record, base_url:)
        raise InvalidResponse, "Invalid project record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }.merge("type" => record["ownerProjectManagerId"] ? "private" : "shared", "url" => "#{base_url.sub(%r{/+\z}, "")}/projects/#{record["id"]}")
      end

      def self.returned_id(record)
        record["id"] if record.is_a?(Hash) && Records.id?(record["id"])
      end

      def self.placeholder = FIELDS.to_h { |field| [field, nil] }.merge("type" => nil, "url" => nil)

      def self.name!(name)
        return name if Records.text?(name, NAME_LIMIT) && !name.strip.empty?

        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} UTF-16 code units"
      end

      def self.description!(text)
        return text if text.nil? || (Records.text?(text, DESCRIPTION_LIMIT) && !text.strip.empty?)

        raise ArgumentError, "description must be nonempty UTF-8 text of at most #{DESCRIPTION_LIMIT} UTF-16 code units"
      end

      def self.type!(type)
        return type if %w[private shared].include?(type)

        raise ArgumentError, "type must be private or shared"
      end

      def self.confirm!(record, desired, base_url:)
        actual = data(record, base_url: base_url)
        unless (desired["id"].nil? || actual.values_at("id", "ownerProjectManagerId") == desired.values_at("id", "ownerProjectManagerId")) &&
               %w[name description type].all? { |field| actual[field] == desired[field] }
          raise InvalidResponse, "Invalid project write response"
        end
      end

      def self.recovery(project)
        return { "action" => "readback-project", "resources" => [{ "type" => "project", "id" => project["id"] }] } if project["id"]

        { "action" => "readback-projects", "resources" => [] }
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.text?(record["name"], NAME_LIMIT) &&
          record.key?("description") && (record["description"].nil? || Records.text?(record["description"], DESCRIPTION_LIMIT)) &&
          record.key?("ownerProjectManagerId") && (record["ownerProjectManagerId"].nil? || Records.id?(record["ownerProjectManagerId"])) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
