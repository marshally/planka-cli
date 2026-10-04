module Planka
  module Workflow
    # Creates spec and ticket cards. Both are project-type cards; a ticket is
    # distinguished only by its "Acceptance criteria" task list, the same marker
    # the picker uses (see Card#ticket?). Card creation is the one step that
    # cannot be undone or safely retried, so it happens first and alone; filling
    # in criteria afterwards is idempotent and resumable.
    #
    # client answers #create_card, #card, #create_task_list and #create_task.
    class Publishing
      CRITERIA_LIST = Card::CRITERIA_LIST
      POSITION_GAP = 65_536

      def initialize(client, base_url:)
        @client = client
        @base_url = base_url.sub(%r{/+\z}, "")
      end

      # A spec: a project card with no acceptance criteria.
      def create_spec(list_id:, name:, description: nil, position: POSITION_GAP)
        card = @client.create_card(list_id, **card_attrs(name, description, position))
        { "card" => card_ref(card) }
      end

      # A ticket: a project card plus one "Acceptance criteria" task list with one
      # incomplete task per criterion, in order.
      def create_ticket(list_id:, name:, criteria:, description: nil, position: POSITION_GAP)
        card = @client.create_card(list_id, **card_attrs(name, description, position))
        fill(card.fetch("id"), criteria, card: card_ref(card))
      end

      # Adds any missing criteria to an already-created card, reusing its
      # "Acceptance criteria" list and skipping criteria already present. Use this
      # to finish a ticket whose creation failed after the card was made.
      def resume_ticket(card_id:, criteria:)
        fill(card_id, criteria, card: card_ref(@client.card(card_id).fetch("item")))
      end

      private

      # Planka rejects an empty-string description, so a card with no description
      # omits the field entirely rather than sending "".
      def card_attrs(name, description, position)
        attrs = { name:, type: "project", position: }
        attrs[:description] = description unless description.nil? || description.empty?
        attrs
      end

      # Reconciles the card's criteria list against the wanted criteria. Safe to
      # repeat: an existing list is reused and criteria already present are kept.
      def fill(card_id, criteria, card:)
        state = { "card" => card, "taskList" => nil, "tasks" => [], "completed" => false }
        included = @client.card(card_id).fetch("included")
        list = criteria_list(card_id, Array(included["taskLists"]))
        state["taskList"] = { "id" => list.fetch("id"), "name" => list["name"] }
        present = Array(included["tasks"]).select { |t| t["taskListId"] == list["id"] }

        criteria.each do |text|
          existing = present.find { |t| t["name"] == text }
          if existing
            state["tasks"] << task_ref(existing, reused: true)
          else
            task = @client.create_task(list.fetch("id"), name: text, position: next_position(present))
            present << task
            state["tasks"] << task_ref(task, reused: false)
          end
        end

        state.merge("completed" => true)
      rescue Planka::Error => e
        raise PartialFailure.new(e.message, state)
      end

      def criteria_list(card_id, task_lists)
        named = task_lists.select { |tl| tl["name"] == CRITERIA_LIST }
        raise Error, "card #{card_id} has #{named.size} #{CRITERIA_LIST} lists" if named.size > 1

        named.first ||
          @client.create_task_list(card_id, name: CRITERIA_LIST, position: next_position(task_lists), showOnFrontOfCard: true)
      end

      def card_ref(card) = { "id" => card.fetch("id"), "name" => card["name"], "url" => "#{@base_url}/cards/#{card.fetch("id")}" }

      def task_ref(task, reused:) = { "id" => task.fetch("id"), "name" => task["name"], "isCompleted" => task["isCompleted"], "reused" => reused }

      def next_position(records) = (records.map { |record| record["position"].to_f }.max || 0) + POSITION_GAP
    end
  end
end
