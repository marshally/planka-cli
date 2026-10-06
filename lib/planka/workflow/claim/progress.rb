module Planka
  module Workflow
    module Claim
      # Owns confirmed effects, uncertain writes, and the canonical claim outcome.
      class Progress
        def initialize(id, base_url:)
          @id, @base_url = id, base_url
          @data = nil
          @changed = false
          @pending_step = nil
        end

        def start(scope)
          @data = { "card" => project_card(scope.card), "userId" => scope.user_id,
            "inProgressListId" => scope.in_progress_list_id, "membershipId" => scope.membership && scope.membership["id"],
            "claimed" => scope.claimed?, "memberAdded" => false, "moved" => false }
        end

        # The block must return a validated write response before confirmation.
        def add_member
          @pending_step = :membership
          member = yield
          @data.merge!("claimed" => true, "memberAdded" => true, "membershipId" => member.fetch("id"))
          confirm
        end

        def move
          @pending_step = :move
          card = yield
          @data["card"] = project_card(card)
          @data["moved"] = true
          confirm
        end

        def result = MutationResult.new(data: @data, changed: @changed)

        def failure(error)
          uncertain = !@pending_step.nil? && !Client.unapplied?(error)
          if uncertain
            @data[@pending_step == :membership ? "memberAdded" : "moved"] = nil
            @data["claimed"] = nil if @pending_step == :membership
          end
          MutationFailure.new(data: @data, changed: @changed ? true : (uncertain ? nil : false),
            uncertain: uncertain, recovery: { "action" => "readback-claim",
              "resources" => [{ "type" => "card", "id" => @id }] })
        end

        private

        def confirm
          @changed = true
          @pending_step = nil
        end

        def project_card(card) = card.slice("id", "name", "listId", "position").merge("url" => "#{@base_url}/cards/#{@id}")
      end
    end
  end
end
