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
        Read.validate!(item, board_id: board_id)
        unless item["name"] == name && item["color"] == color && labels.none? { |record| record["id"] == item["id"] }
          raise InvalidResponse, "Invalid created label"
        end

        MutationResult.new(data: Read.project(item), changed: true)
      rescue *Read::ERRORS => error
        uncertain = !Client.unapplied?(error)
        id = item["id"] if item.is_a?(Hash) && Records.id?(item["id"]) && labels.none? { |record| record["id"] == item["id"] }
        resources = [{ "type" => "board", "id" => board_id }]
        resources << { "type" => "label", "id" => id } if id
        data = Read::FIELDS.to_h { |field| [field, nil] }.merge("id" => id, "boardId" => board_id) if uncertain
        raise MutationFailure.new(data: data, changed: uncertain ? nil : false, uncertain: uncertain,
                                  recovery: { "action" => "readback-labels", "resources" => resources })
      end
      private_class_method :create
    end
  end
end
