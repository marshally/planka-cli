module Planka
  module Workflow
    module Claim
      # Validated observations and response invariants for one card's claim.
      class Scope
        attr_reader :card, :user_id, :membership, :in_progress_list_id

        def self.read(client, id) = new(client, id)

        def initialize(client, id)
          @id, @user_id = id, Records.user!(client.me).fetch("id")
          load(client)
        end

        def claimed? = !@membership.nil?
        def in_progress? = @card.fetch("listId") == @in_progress_list_id

        def created_membership(response)
          member = response["item"]
          unless member.is_a?(Hash) && Records.id?(member["id"]) && member["cardId"] == @id && member["userId"] == @user_id
            raise InvalidResponse, "Invalid created card membership"
          end
          member
        end

        def moved_card(response)
          moved = validate_card!(response)
          unless moved["listId"] == @in_progress_list_id && moved["boardId"] == @card.fetch("boardId")
            raise InvalidResponse, "Invalid moved card list"
          end
          moved
        end

        private

        def load(client)
          @card = validate_card!(client.card(@id)["item"])
          included = client.board(@card.fetch("boardId"))
          lists, memberships = included.values_at("lists", "cardMemberships")
          validate_lists!(lists)
          validate_memberships!(memberships)
          progress = lists.select { |list| list["name"] == Workflow::Card::IN_PROGRESS_LIST }
          unless progress.size == 1
            raise DependencyUnavailable, "Expected exactly one in-progress list on the card's board; correct the list names before claiming"
          end
          @in_progress_list_id = progress.first.fetch("id")
          @membership = memberships.find { |record| record["cardId"] == @id && record["userId"] == @user_id }
        end

        def validate_lists!(lists)
          unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && Records.id?(list["id"]) &&
              list["boardId"] == @card["boardId"] && list["name"].is_a?(String) } &&
              lists.map { |list| list["id"] }.uniq.size == lists.size && lists.any? { |list| list["id"] == @card["listId"] }
            raise InvalidResponse, "Invalid claim scope records"
          end
        end

        def validate_memberships!(memberships)
          unless memberships.is_a?(Array) && memberships.all? { |member| member.is_a?(Hash) && Records.id?(member["cardId"]) &&
              (member["id"].nil? || Records.id?(member["id"])) && member["userId"].is_a?(String) && !member["userId"].empty? }
            raise InvalidResponse, "Invalid claim scope records"
          end
        end

        def validate_card!(card)
          unless card.is_a?(Hash) && card["id"] == @id && Records.id?(card["boardId"]) && Records.id?(card["listId"]) &&
              card["name"].is_a?(String) && card["position"].is_a?(Numeric) && card["position"].finite? && card["position"] >= 0
            raise InvalidResponse, "Invalid claim card"
          end
          card
        end
      end
    end
  end
end
