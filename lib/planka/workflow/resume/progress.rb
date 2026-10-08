module Planka
  module Workflow
    module Resume
      # Owns confirmed effects, uncertain writes, and the canonical resume outcome.
      class Progress < MutationProgress
        def initialize(id, base_url:)
          super(id)
          @base_url = base_url
        end

        def keep(task) = @data["tasks"] << project_task(task, created: false)

        # Each block must return a validated write response before confirmation.
        def create_task_list
          step({ "taskList" => { "id" => nil, "name" => Workflow::Card::CRITERIA_LIST, "created" => nil } }) do
            list = yield
            @data["taskList"] = { "id" => list["id"], "name" => list["name"], "created" => true }
            list
          end
        end

        def create_task(name)
          step({ "tasks" => { "id" => nil, "name" => name, "isCompleted" => nil, "created" => nil } }) do
            task = yield
            @data["tasks"] << project_task(task, created: true)
            task
          end
        end

        private

        def initial_data(scope)
          card = scope.card
          list = scope.task_list
          { "card" => { "id" => @id, "name" => card["name"], "url" => "#{@base_url}/cards/#{@id}" },
            "taskList" => list && { "id" => list["id"], "name" => list["name"], "created" => false },
            "tasks" => [] }
        end

        def record_uncertain_step(step)
          key, payload = step.first
          key == "tasks" ? @data["tasks"] << payload : @data[key] = payload
        end

        def recovery
          list_id = @data&.dig("taskList", "id")
          { "action" => "resume-ticket", "resources" => [{ "type" => "card", "id" => @id },
                                                         (list_id && { "type" => "task-list", "id" => list_id })].compact }
        end

        def project_task(task, created:) = task.slice("id", "name", "isCompleted").merge("created" => created)
      end
    end
  end
end
