module Planka
  module Workflow
    module Claim
      # Owns confirmed effects, uncertain writes, and the canonical claim outcome.
      class Progress < MutationProgress
        def initialize(id, base_url:)
          super(id)
          @base_url = base_url
        end

        # The block must return a validated write response before confirmation.
        def add_member
          step(:membership) do
            member = yield
            @data.merge!("claimed" => true, "memberAdded" => true, "membershipId" => member.fetch("id"))
            nil
          end
        end

        def move
          step(:move) do
            card = yield
            @data["card"] = project_card(card)
            @data["moved"] = true
            nil
          end
        end

        private

        def initial_data(scope)
          { "card" => project_card(scope.card), "userId" => scope.user_id,
            "inProgressListId" => scope.in_progress_list_id, "membershipId" => scope.membership && scope.membership["id"],
            "claimed" => scope.claimed?, "memberAdded" => false, "moved" => false }
        end

        def record_uncertain_step(step)
          @data[step == :membership ? "memberAdded" : "moved"] = nil
          @data["claimed"] = nil if step == :membership
        end

        def recovery = { "action" => "readback-claim", "resources" => [{ "type" => "card", "id" => @id }] }

        def project_card(card) = card.slice("id", "name", "listId", "position").merge("url" => "#{@base_url}/cards/#{@id}")
      end
    end
  end
end
