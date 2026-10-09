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
            @unconfirmed_task_list_id = nil
            @unconfirmed_task = nil
          end

          def start(scope)
            @criteria.start(scope)
            @started = true
          end

          def keep(task) = @criteria.keep(task)

          def create_task_list(&block)
            @criteria.create_task_list(&block)
          rescue Criteria::Scope::UnconfirmedIdentity => error
            @unconfirmed_task_list_id = error.trusted_id
            raise
          end

          def create_task(name)
            @criteria.create_task(name) do
              task = yield
              if task["isCompleted"] != false
                raise Criteria::Scope::UnconfirmedIdentity.new(task["id"], "Created criterion is not incomplete")
              end

              task
            end
          rescue Criteria::Scope::UnconfirmedIdentity => error
            @unconfirmed_task = { name: name, id: error.trusted_id }
            raise
          end

          def result
            result = @criteria.result
            MutationResult.new(data: result.data.merge("card" => @card), changed: true)
          end

          def failure(error)
            return MutationFailure.new(data: initial_data, changed: true, uncertain: false, recovery: recovery) unless @started

            failure = @criteria.failure(error)
            data = failure.data.merge("card" => @card)
            preserve_unconfirmed_identities(data)
            recovery = failure.recovery
            list_id = data.dig("taskList", "id")
            if list_id && recovery && !recovery.fetch("resources").any? { |resource| resource == { "type" => "task-list", "id" => list_id } }
              recovery = recovery.merge("resources" => recovery.fetch("resources") + [{ "type" => "task-list", "id" => list_id }])
            end
            MutationFailure.new(data: data, changed: true,
                                uncertain: failure.uncertain, recovery: recovery)
          end

          private

          def initial_data = { "card" => @card, "taskList" => nil, "tasks" => [] }

          def preserve_unconfirmed_identities(data)
            if @unconfirmed_task_list_id && data["taskList"]
              data["taskList"] = data["taskList"].merge("id" => @unconfirmed_task_list_id)
            end
            return unless @unconfirmed_task

            index = data["tasks"].rindex { |task| task["name"] == @unconfirmed_task[:name] && task["created"].nil? }
            data["tasks"][index] = data["tasks"][index].merge("id" => @unconfirmed_task[:id]) if index
          end

          def recovery
            { "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => @card.fetch("id") }] }
          end
        end
      end
    end
  end
end
