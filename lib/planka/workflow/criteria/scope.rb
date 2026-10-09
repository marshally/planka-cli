module Planka
  module Workflow
    module Criteria
      # Validated observations and response invariants for one ticket's criteria.
      class Scope
        attr_reader :card, :task_list, :tasks

        class UnconfirmedIdentity < InvalidResponse
          attr_reader :trusted_id

          def initialize(trusted_id, message)
            @trusted_id = trusted_id
            super(message)
          end
        end

        def self.read(client, id) = new(client, id)

        def initialize(client, id)
          @id = id
          load(client.card(id))
        end

        def task_list_position = Position.after(@task_lists)

        def created_task_list(record)
          identity = created_identity(record, "cardId", @id, @task_list_ids)
          invalid_created_record!("Invalid created criteria list", identity) unless
            identity && record["name"] == Workflow::Card::CRITERIA_LIST && Records.position?(record["position"])

          @task_list_ids << identity
          record
        end

        def created_task(record, task_list_id, name)
          identity = created_identity(record, "taskListId", task_list_id, @task_ids)
          valid = identity && record["name"] == name && [true, false].include?(record["isCompleted"]) &&
                  record["linkedCardId"].nil? && Records.position?(record["position"])
          invalid_created_record!("Invalid created criterion", identity) unless valid

          @task_ids << identity
          record
        end

        private

        def load(document)
          @card = validate_card!(document["item"])
          included = document["included"]
          raise InvalidResponse, "Invalid ticket records" unless included.is_a?(Hash)

          @task_lists = validate_task_lists!(included["taskLists"])
          tasks = validate_tasks!(included["tasks"])
          @task_list_ids = @task_lists.map { |list| list["id"] }
          @task_ids = tasks.map { |task| task["id"] }
          named = @task_lists.select { |list| list["name"] == Workflow::Card::CRITERIA_LIST }
          if named.size > 1
            raise ReferenceError.new("Card has #{named.size} #{Workflow::Card::CRITERIA_LIST} lists; candidate IDs: " \
                                     "#{named.map { |list| list["id"] }.join(", ")}", code: "ambiguous_criteria_list", status: 1)
          end

          @task_list = named.first
          @tasks = @task_list ? tasks.select { |task| task["taskListId"] == @task_list["id"] } : []
        end

        def validate_card!(card)
          raise InvalidResponse, "Invalid ticket card" unless card.is_a?(Hash) && card["id"] == @id && card["name"].is_a?(String)

          card
        end

        def validate_task_lists!(lists)
          unless lists.is_a?(Array) && lists.all? { |list|
            list.is_a?(Hash) && Records.id?(list["id"]) && list["cardId"] == @id && list["name"].is_a?(String) &&
            Records.position?(list["position"])
          }
            raise InvalidResponse, "Invalid ticket records"
          end

          lists
        end

        # Linked tasks may carry no name; criteria match only named tasks.
        def validate_tasks!(tasks)
          unless tasks.is_a?(Array) && tasks.all? { |task|
            task.is_a?(Hash) && Records.id?(task["id"]) && @task_lists.any? { |list| list["id"] == task["taskListId"] } &&
            (task["name"].is_a?(String) || task["name"].nil?) && [true, false].include?(task["isCompleted"]) &&
            Records.position?(task["position"])
          }
            raise InvalidResponse, "Invalid ticket records"
          end

          tasks
        end

        def created_identity(record, parent_key, parent_id, existing_ids)
          return unless record.is_a?(Hash) && Records.id?(record["id"]) && record[parent_key] == parent_id
          return if existing_ids.include?(record["id"])

          record["id"]
        end

        def invalid_created_record!(message, identity)
          if identity
            raise UnconfirmedIdentity.new(identity, message)
          end

          raise InvalidResponse, message
        end
      end
    end
  end
end
