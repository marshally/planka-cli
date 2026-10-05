module Planka
  module Workflow
    # Validated observations and response invariants for one card's claim.
    class ClaimScope
      attr_reader :card, :user_id, :membership, :in_progress_list_id

      def self.read(client, id) = new(client, id)

      def initialize(client, id)
        user = client.me
        unless user.is_a?(Hash) && user["id"].is_a?(String) && !user["id"].empty?
          raise InvalidResponse, "Invalid signed-in user"
        end
        @id, @user_id = id, user.fetch("id")
        load(client)
      end

      def claimed? = !@membership.nil?
      def in_progress? = @card.fetch("listId") == @in_progress_list_id

      def created_membership(response)
        member = response["item"]
        unless member.is_a?(Hash) && id?(member["id"]) && member["cardId"] == @id && member["userId"] == @user_id
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
        progress = lists.select { |list| list["name"] == Card::IN_PROGRESS_LIST }
        unless progress.size == 1
          raise DependencyUnavailable, "Expected exactly one in-progress list on the card's board; correct the list names before claiming"
        end
        @in_progress_list_id = progress.first.fetch("id")
        @membership = memberships.find { |record| record["cardId"] == @id && record["userId"] == @user_id }
      end

      def validate_lists!(lists)
        unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && id?(list["id"]) &&
            list["boardId"] == @card["boardId"] && list["name"].is_a?(String) } &&
            lists.map { |list| list["id"] }.uniq.size == lists.size && lists.any? { |list| list["id"] == @card["listId"] }
          raise InvalidResponse, "Invalid claim scope records"
        end
      end

      def validate_memberships!(memberships)
        unless memberships.is_a?(Array) && memberships.all? { |member| member.is_a?(Hash) && id?(member["cardId"]) &&
            (member["id"].nil? || id?(member["id"])) && member["userId"].is_a?(String) && !member["userId"].empty? }
          raise InvalidResponse, "Invalid claim scope records"
        end
      end

      def validate_card!(card)
        unless card.is_a?(Hash) && card["id"] == @id && id?(card["boardId"]) && id?(card["listId"]) &&
            card["name"].is_a?(String) && card["position"].is_a?(Numeric) && card["position"].finite? && card["position"] >= 0
          raise InvalidResponse, "Invalid claim card"
        end
        card
      end

      def id?(value) = value.is_a?(String) && value.match?(/\A\d+\z/)
    end
  end
end
