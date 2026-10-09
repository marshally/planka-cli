module Planka
  module Workflow
    module Criteria
      # Fills exact-text criteria on a card while delegating effect projection and
      # recovery policy to the supplied progress collaborator.
      class Fill
        # Planka's task name limit, in UTF-16 code units.
        CRITERION_LIMIT = 1024

        def self.call(client, id, criteria:, progress:)
          new(client, id, criteria, progress).call
        end

        def initialize(client, id, criteria, progress)
          @client, @id, @criteria, @progress = client, id, criteria, progress
        end

        def call
          scope = Scope.read(@client, @id)
          @progress.start(scope)
          task_list_id = ensure_task_list(scope)
          fill(scope, task_list_id)
          @progress.result
        rescue *OPERATION_ERRORS => error
          raise @progress.failure(error)
        end

        private

        def ensure_task_list(scope)
          return scope.task_list.fetch("id") if scope.task_list

          @progress.create_task_list do
            scope.created_task_list(@client.create_task_list(@id, name: Workflow::Card::CRITERIA_LIST,
                                                                  position: scope.task_list_position, showOnFrontOfCard: true))
          end.fetch("id")
        end

        # Criteria already present by exact name are kept; missing ones are appended.
        def fill(scope, task_list_id)
          present = scope.tasks.dup
          @criteria.each do |name|
            existing = present.find { |task| task["name"] == name }
            next @progress.keep(existing) if existing

            present << @progress.create_task(name) do
              scope.created_task(@client.create_task(task_list_id, name: name, position: Position.after(present)), task_list_id, name)
            end
          end
        end
      end
    end
  end
end
