module Planka
  class Labels
    class Update
      def self.read(client, reference, board_id:, attributes:, base_url:)
        before = Read.read(client, reference, board_id: board_id, base_url: base_url)
        return MutationResult.new(data: before, changed: false) if attributes.all? { |field, value| before[field] == value }

        update(client, before, attributes)
      end

      def self.update(client, before, attributes)
        item = client.update_label(before.fetch("id"), **attributes.transform_keys(&:to_sym))
        Read.validate!(item, board_id: before.fetch("boardId"))
        unless item["id"] == before["id"] && %w[name color].all? { |field| item[field] == attributes.fetch(field, before[field]) }
          raise InvalidResponse, "Invalid updated label"
        end

        MutationResult.new(data: Read.project(item), changed: true)
      rescue *Read::ERRORS => error
        uncertain = !Client.unapplied?(error)
        data = before.dup
        attributes.each_key { |field| data[field] = nil } if uncertain
        data["updatedAt"] = nil if uncertain
        raise MutationFailure.new(data: data, changed: uncertain ? nil : false, uncertain: uncertain,
                                  recovery: { "action" => "readback-label", "resources" => [{ "type" => "board", "id" => before["boardId"] }, { "type" => "label", "id" => before["id"] }] })
      end
      private_class_method :update
    end
  end
end
