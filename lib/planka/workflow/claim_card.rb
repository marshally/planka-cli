module Planka
  module Workflow
    # Canonical claim with independently reported membership and move effects.
    class ClaimCard
      POSITION = 65_535

      def self.read(client, id, base_url:)
        new(client, id, base_url).call
      end

      def initialize(client, id, base_url)
        @client, @id, @base_url = client, id, base_url
        @data = nil
        @changed = false
        @writing = false
      end

      def call
        prepare
        unless @data["claimed"]
          member = write { validate_membership!(@client.add_card_member(@id, @data.fetch("userId"))) }
          @data.merge!("claimed" => true, "memberAdded" => true, "membershipId" => member.fetch("id"))
          @changed = true
        end
        unless @data.fetch("card").fetch("listId") == @data.fetch("inProgressListId")
          moved = write { @client.move_card(@id, @data.fetch("inProgressListId"), position: POSITION, idempotent: false) }
          validate_card!(moved)
          unless moved["listId"] == @data.fetch("inProgressListId") && moved["boardId"] == @board_id
            raise InvalidResponse, "Invalid moved card list"
          end
          @data["card"] = project_card(moved)
          @data["moved"] = true
          @changed = true
          @writing = false
        end
        MutationResult.new(data: @data, changed: @changed)
      rescue Planka::Error, SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError => error
        uncertain = @writing && !error.is_a?(Client::HTTPError) && !Client::UNSENT.any? { |type| error.is_a?(type) }
        if uncertain && @data
          @data[@step] = nil
          @data["claimed"] = nil if @step == "memberAdded"
        end
        raise MutationFailure.new(data: @data, changed: @changed ? true : (uncertain ? nil : false),
          uncertain: uncertain, recovery: { "action" => "readback-claim",
            "resources" => [{ "type" => "card", "id" => @id }] })
      end

      private

      def prepare
        user = @client.me
        unless user.is_a?(Hash) && user["id"].is_a?(String) && !user["id"].empty?
          raise InvalidResponse, "Invalid signed-in user"
        end
        response = @client.card(@id)
        card = response["item"]
        validate_card!(card)
        @board_id = card.fetch("boardId")
        included = @client.board(card.fetch("boardId"))
        lists, memberships = included.values_at("lists", "cardMemberships")
        unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && id?(list["id"]) &&
            list["boardId"] == card["boardId"] && list["name"].is_a?(String) } &&
            lists.map { |list| list["id"] }.uniq.size == lists.size && lists.any? { |list| list["id"] == card["listId"] } &&
            memberships.is_a?(Array) && memberships.all? { |member| member.is_a?(Hash) && id?(member["cardId"]) &&
              member["userId"].is_a?(String) && !member["userId"].empty? }
          raise InvalidResponse, "Invalid claim scope records"
        end
        progress = lists.select { |list| list["name"] == Card::IN_PROGRESS_LIST }
        unless progress.size == 1
          raise DependencyUnavailable, "Expected exactly one in-progress list on the card's board; correct the list names before claiming"
        end
        member = memberships.find { |record| record["cardId"] == @id && record["userId"] == user["id"] }
        @data = { "card" => project_card(card), "userId" => user["id"], "inProgressListId" => progress.first["id"],
          "membershipId" => member && member["id"], "claimed" => !member.nil?, "memberAdded" => false, "moved" => false }
      end

      def write
        @step = @data["claimed"] ? "moved" : "memberAdded"
        @writing = true
        result = yield
        @writing = false if @step == "memberAdded"
        result
      end

      def validate_membership!(response)
        member = response["item"]
        unless member.is_a?(Hash) && id?(member["id"]) && member["cardId"] == @id && member["userId"] == @data["userId"]
          raise InvalidResponse, "Invalid created card membership"
        end
        member
      end

      def validate_card!(card)
        unless card.is_a?(Hash) && card["id"] == @id && id?(card["boardId"]) && id?(card["listId"]) &&
            card["name"].is_a?(String) && card["position"].is_a?(Numeric) && card["position"].finite? && card["position"] >= 0
          raise InvalidResponse, "Invalid claim card"
        end
      end

      def id?(value) = value.is_a?(String) && value.match?(/\A\d+\z/)
      def project_card(card) = card.slice("id", "name", "listId", "position").merge("url" => "#{@base_url}/cards/#{@id}")
    end
  end
end
