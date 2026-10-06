module Planka
  class Labels
    class Create
      def self.read(client, board_id:, name:, color:, position: nil, base_url:)
        labels = Read.read(client, board_id: board_id, base_url: base_url).data
        position ||= Position.after(labels)
        create(client, labels, board_id, name, color, position)
      rescue CollectionFailure => error
        raise error.cause
      end

      def self.create(client, labels, board_id, name, color, position)
        item = client.create_label(board_id, name: name, color: color, position: position)
        confirm_write!(item, labels, board_id, name, color)
        MutationResult.new(data: Read.project(item), changed: true)
      rescue *Read::ERRORS => error
        raise write_failure(error, item, labels, board_id)
      end

      def self.confirm_write!(item, labels, board_id, name, color)
        Read.validate!(item, board_id: board_id)
        unless item["name"] == name && item["color"] == color && labels.none? { |record| record["id"] == item["id"] }
          raise InvalidResponse, "Invalid created label"
        end
      end

      def self.write_failure(error, item, labels, board_id)
        uncertain = !Client.unapplied?(error)
        id = created_id(item, labels)
        data = unknown_label(board_id, id) if uncertain
        MutationFailure.new(data: data, changed: uncertain ? nil : false, uncertain: uncertain,
                            recovery: { "action" => "readback-labels", "resources" => recovery_resources(board_id, id) })
      end

      def self.created_id(item, labels)
        item["id"] if item.is_a?(Hash) && Records.id?(item["id"]) && labels.none? { |record| record["id"] == item["id"] }
      end

      def self.unknown_label(board_id, id)
        Read::FIELDS.to_h { |field| [field, nil] }.merge("id" => id, "boardId" => board_id)
      end

      def self.recovery_resources(board_id, id)
        resources = [{ "type" => "board", "id" => board_id }]
        resources << { "type" => "label", "id" => id } if id
        resources
      end

      private_class_method :create, :confirm_write!, :write_failure, :created_id, :unknown_label, :recovery_resources
    end
  end
end
