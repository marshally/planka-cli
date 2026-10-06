module Planka
  class Labels
    class Delete
      def self.read(client, reference, board_id:, base_url:)
        before = Read.read(client, reference, board_id: board_id, base_url: base_url)
        delete(client, before)
      end

      def self.delete(client, before)
        item = client.delete_label(before.fetch("id"))
        Read.validate!(item, board_id: before.fetch("boardId"))
        raise InvalidResponse, "Invalid deleted label" unless item["id"] == before["id"]

        MutationResult.new(data: Read.project(item).merge("deleted" => true), changed: true)
      rescue *Read::ERRORS => error
        uncertain = !Client.unapplied?(error)
        raise MutationFailure.new(data: before.merge("deleted" => uncertain ? nil : false), changed: uncertain ? nil : false, uncertain: uncertain,
                                  recovery: { "action" => "readback-label", "resources" => [{ "type" => "board", "id" => before["boardId"] }, { "type" => "label", "id" => before["id"] }] })
      end
      private_class_method :delete
    end
  end
end
