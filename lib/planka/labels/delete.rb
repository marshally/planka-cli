module Planka
  class Labels
    class Delete
      def self.read(client, reference, board_id:, base_url:)
        before = Read.read(client, reference, board_id: board_id, base_url: base_url)
        delete(client, before)
      end

      def self.delete(client, before)
        item = client.delete_label(before.fetch("id"))
        confirm_write!(item, before)
        MutationResult.new(data: Read.project(item).merge("deleted" => true), changed: true)
      rescue *Read::ERRORS => error
        raise write_failure(error, before)
      end

      def self.confirm_write!(item, before)
        Read.validate!(item, board_id: before.fetch("boardId"))
        raise InvalidResponse, "Invalid deleted label" unless item["id"] == before["id"]
      end

      def self.write_failure(error, before)
        uncertain = !Client.unapplied?(error)
        MutationFailure.new(data: before.merge("deleted" => uncertain ? nil : false), changed: uncertain ? nil : false, uncertain: uncertain,
                            recovery: recovery(before))
      end

      def self.recovery(before)
        { "action" => "readback-label", "resources" => [{ "type" => "board", "id" => before["boardId"] }, { "type" => "label", "id" => before["id"] }] }
      end

      private_class_method :delete, :confirm_write!, :write_failure, :recovery
    end
  end
end
