module Planka
  module Workflow
    module Create
      # Publishes one project card, then fills its acceptance criteria.
      module Ticket
        def self.create(client, list:, criteria:, base_url:, board_id: nil, **attributes)
          created = create_card(client, list, board_id:, base_url:, **attributes)
          progress = Progress.new(created.data, base_url: base_url)
          Criteria::Fill.call(client, created.data.fetch("id"), criteria: criteria, progress: progress)
        end

        def self.create_card(client, list, board_id:, base_url:, **attributes)
          Boards::Cards.new(client, board_id: board_id).create(list, **attributes, type: "project")
        rescue MutationFailure => failure
          card = failure.data.merge("url" => failure.data["id"] && "#{base_url}/cards/#{failure.data["id"]}")
          data = { "card" => card, "taskList" => nil, "tasks" => [] }
          raise MutationFailure.new(data: data, changed: failure.changed, uncertain: failure.uncertain,
                                    recovery: failure.recovery), cause: failure.cause
        end
        private_class_method :create_card

        # Adds ticket creation's confirmed card effect to the shared criteria
        # tracker while leaving resume projection and recovery policy intact.
        class Progress
          def initialize(card, base_url:)
            @card = card.merge("url" => "#{base_url}/cards/#{card.fetch("id")}")
            @criteria = Resume::Progress.new(card.fetch("id"), base_url: base_url)
            @started = false
          end

          def start(scope)
            @criteria.start(scope)
            @started = true
          end

          def keep(task) = @criteria.keep(task)
          def create_task_list(&block) = @criteria.create_task_list(&block)

          def create_task(name)
            @criteria.create_task(name) do
              task = yield
              raise InvalidResponse, "Created criterion is not incomplete" unless task["isCompleted"] == false

              task
            end
          end

          def result
            result = @criteria.result
            MutationResult.new(data: result.data.merge("card" => @card), changed: true)
          end

          def failure(error)
            return MutationFailure.new(data: initial_data, changed: true, uncertain: false, recovery: recovery) unless @started

            failure = @criteria.failure(error)
            MutationFailure.new(data: failure.data.merge("card" => @card), changed: true,
                                uncertain: failure.uncertain, recovery: failure.recovery)
          end

          private

          def initial_data = { "card" => @card, "taskList" => nil, "tasks" => [] }

          def recovery
            { "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => @card.fetch("id") }] }
          end
        end
      end
    end
  end
end
