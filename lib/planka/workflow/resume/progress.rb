module Planka
  module Workflow
    module Resume
      # Owns confirmed effects, uncertain writes, and the canonical resume outcome.
      class Progress
        def initialize(id, base_url:)
          @id, @base_url = id, base_url
          @data = nil
          @changed = false
          @pending = nil
        end

        def start(scope)
          card = scope.card
          list = scope.task_list
          @data = { "card" => { "id" => @id, "name" => card["name"], "url" => "#{@base_url}/cards/#{@id}" },
                    "taskList" => list && { "id" => list["id"], "name" => list["name"], "created" => false },
                    "tasks" => [] }
        end

        def keep(task) = @data["tasks"] << project_task(task, created: false)

        # Each block must return a validated write response before confirmation.
        def create_task_list
          @pending = { "taskList" => { "id" => nil, "name" => Workflow::Card::CRITERIA_LIST, "created" => nil } }
          list = yield
          @data["taskList"] = { "id" => list["id"], "name" => list["name"], "created" => true }
          confirm
          list
        end

        def create_task(name)
          @pending = { "tasks" => { "id" => nil, "name" => name, "isCompleted" => nil, "created" => nil } }
          task = yield
          @data["tasks"] << project_task(task, created: true)
          confirm
          task
        end

        def result = MutationResult.new(data: @data, changed: @changed)

        def failure(error)
          uncertain = !@pending.nil? && !Client.unapplied?(error)
          record_uncertain_step if uncertain
          MutationFailure.new(data: @data, changed: @changed ? true : (uncertain ? nil : false),
                              uncertain: uncertain, recovery: { "action" => "resume-ticket", "resources" => recovery_resources })
        end

        private

        def confirm
          @changed = true
          @pending = nil
        end

        def record_uncertain_step
          key, step = @pending.first
          key == "tasks" ? @data["tasks"] << step : @data[key] = step
        end

        def recovery_resources
          list_id = @data&.dig("taskList", "id")
          [{ "type" => "card", "id" => @id }, (list_id && { "type" => "task-list", "id" => list_id })].compact
        end

        def project_task(task, created:) = task.slice("id", "name", "isCompleted").merge("created" => created)
      end
    end
  end
end
