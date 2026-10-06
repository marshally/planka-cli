module Planka
  class Tasks
    # Executes a single native mutation and preserves known versus uncertain effects.
    module Write
      def self.perform(snapshot, known, expected:, operation:, changed_fields: expected.keys)
        record = yield
        validate_response!(record, known, expected)
        success(snapshot, record, operation)
      rescue *OPERATION_ERRORS => error
        raise failure(error, snapshot, known, expected, operation, changed_fields)
      end

      def self.validate_response!(record, known, expected)
        Snapshot.validate!(record)
        unless record["taskListId"] == expected.fetch("taskListId") &&
               (!known["id"] || record["id"] == known["id"]) &&
               expected.reject { |key, _| key == "position" }.all? { |key, value| record[key] == value }
          raise InvalidResponse, "Invalid task mutation response"
        end
      end

      def self.success(snapshot, record, operation)
        data = snapshot.project(record)
        data["deleted"] = true if operation == :delete
        MutationResult.new(data: data, changed: true)
      end

      def self.failure(error, snapshot, known, expected, operation, changed_fields)
        uncertain = !Client.unapplied?(error)
        MutationFailure.new(data: failure_data(known, operation, changed_fields, uncertain),
                            changed: uncertain ? nil : false, uncertain: uncertain,
                            recovery: { "action" => "readback-task", "resources" => recovery_resources(snapshot, known, expected) })
      end

      def self.failure_data(known, operation, changed_fields, uncertain)
        data = known.dup
        changed_fields.each { |key| data[key] = nil } if uncertain && operation != :create
        data["deleted"] = uncertain ? nil : false if operation == :delete
        data
      end

      def self.recovery_resources(snapshot, known, expected)
        resources = [{ "type" => "card", "id" => snapshot.card_id }, { "type" => "task-list", "id" => expected["taskListId"] }]
        resources << { "type" => "task", "id" => known["id"] } if known["id"]
        resources
      end
      private_class_method :validate_response!, :success, :failure, :failure_data, :recovery_resources
    end
  end
end
