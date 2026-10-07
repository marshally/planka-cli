module Planka
  module Workflow
    module Resume
      # Validated observations and response invariants for one ticket's criteria.
      class Scope
        attr_reader :card, :task_list, :tasks

        def self.read(client, id) = new(client, id)

        def initialize(client, id)
          @id = id
          load(client.card(id))
        end

        def task_list_position = Position.after(@task_lists)

        def created_task_list(record)
          unless record.is_a?(Hash) && Records.id?(record["id"]) && record["cardId"] == @id &&
                 record["name"] == Workflow::Card::CRITERIA_LIST
            raise InvalidResponse, "Invalid created criteria list"
          end

          record
        end

        def created_task(record, task_list_id, name)
          unless record.is_a?(Hash) && Records.id?(record["id"]) && record["taskListId"] == task_list_id &&
                 record["name"] == name && [true, false].include?(record["isCompleted"])
            raise InvalidResponse, "Invalid created criterion"
          end

          record
        end

        private

        def load(document)
          @card = validate_card!(document["item"])
          included = document["included"]
          raise InvalidResponse, "Invalid ticket records" unless included.is_a?(Hash)

          @task_lists = validate_task_lists!(included["taskLists"])
          tasks = validate_tasks!(included["tasks"])
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
      end
    end
  end
end
