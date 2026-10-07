module Planka
  module Workflow
    module Resume
      # Fills an existing ticket's missing acceptance criteria; each write confirms
      # its own response. It never creates a card.
      class Ticket
        # Planka's task name limit, in UTF-16 code units.
        CRITERION_LIMIT = 1024

        def self.read(client, id, criteria:, base_url:)
          new(client, id, criteria, base_url).call
        end

        def initialize(client, id, criteria, base_url)
          @client, @id, @criteria = client, id, criteria
          @progress = Progress.new(id, base_url: base_url)
        end

        def call
          scope = Scope.read(@client, @id)
          @progress.start(scope)
          task_list_id = ensure_task_list(scope)
          fill(scope, task_list_id)
          @progress.result
        rescue Planka::Error, *Client::NETWORK_ERRORS => error
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
