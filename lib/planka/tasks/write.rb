module Planka
  class Tasks
    # Executes a single native mutation and preserves known versus uncertain effects.
    module Write
      def self.perform(snapshot, known, expected:, operation:, changed_fields: expected.keys)
        result = yield
        Snapshot.validate!(result)
        unless result["taskListId"] == expected.fetch("taskListId") &&
               (!known["id"] || result["id"] == known["id"]) &&
               expected.reject { |key, _| key == "position" }.all? { |key, value| result[key] == value }
          raise InvalidResponse, "Invalid task mutation response"
        end

        data = snapshot.project(result)
        data["deleted"] = true if operation == :delete
        MutationResult.new(data: data, changed: true)
      rescue *OPERATION_ERRORS => error
        uncertain = !Client.unapplied?(error)
        data = known.dup
        changed_fields.each { |key| data[key] = nil } if uncertain && operation != :create
        data["deleted"] = uncertain ? nil : false if operation == :delete
        resources = [{ "type" => "card", "id" => snapshot.card_id }, { "type" => "task-list", "id" => expected["taskListId"] }]
        resources << { "type" => "task", "id" => known["id"] } if known["id"]
        raise MutationFailure.new(data: data, changed: uncertain ? nil : false, uncertain: uncertain,
                                  recovery: { "action" => "readback-task", "resources" => resources })
      end
    end
  end
end
