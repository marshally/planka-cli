module Planka
  module Cards
    # Reads and changes assignments within one card scope. Each operation observes
    # current state through the supplied authenticated client.
    class Members
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def initialize(client, card_id:, board_id: nil)
        @client, @card_id, @board_id = client, card_id, board_id
      end

      def all(name: nil, limit: nil)
        data = []
        card, board = Scope.read(@client, card_id: @card_id, board_id: @board_id)
        hydrate_members!(data, card, identities(board), Scope.card_id(card))
        collection(data, name: name, limit: limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: collection(data, name: name, limit: limit).data)
      end

      def find(reference) = assigned!(observe_member(reference))
      def add(reference) = mutate(reference, assigned: true)
      def remove(reference) = mutate(reference, assigned: false)

      private

      def observe_member(reference)
        card, board = Scope.read(@client, card_id: @card_id, board_id: @board_id)
        users = identities(board)
        user = resolve_user(reference, users, board, Scope.board_id(card))
        data = []
        hydrate_members!(data, card, users, Scope.card_id(card))
        assignment(data, user) || member_data(user, Scope.card_id(card))
      end

      def identities(board)
        users = board["users"]
        unless users.is_a?(Array) && users.all? { |user|
          user.is_a?(Hash) && Records.id?(user["id"]) &&
          user["name"].is_a?(String) && (user["username"].nil? || user["username"].is_a?(String))
        } &&
               users.map { |user| user["id"] }.uniq.size == users.size
          raise InvalidResponse, "Invalid member identities"
        end

        users
      end

      def resolve_user(reference, users, board, board_id)
        members = board["boardMemberships"]
        unless members.is_a?(Array) && members.all? { |member|
          member.is_a?(Hash) &&
          member["boardId"] == board_id && Records.id?(member["userId"])
        }
          raise InvalidResponse, "Invalid board member scope"
        end

        scoped = users.select { |user| members.any? { |member| member["userId"] == user["id"] } }
        Reference.resolve(scoped, reference, resource: "user")
      end

      def hydrate_members!(data, card, users, card_id)
        included = card["included"]
        raise InvalidResponse, "Invalid card relations" unless included.is_a?(Hash)

        records = included["cardMemberships"]
        raise InvalidResponse, "Invalid membership collection" unless records.is_a?(Array)

        records.each do |record|
          validate_membership!(record, card_id: card_id)
          user = users.find { |identity| identity["id"] == record["userId"] }
          raise InvalidResponse, "Missing member identity" unless user
          if data.any? { |member| member["id"] == user["id"] || member["membershipId"] == record["id"] }
            raise InvalidResponse, "Duplicate membership"
          end

          data << member_data(user, card_id, record)
        end
      end

      def assignment(data, user) = data.find { |record| record["id"] == user["id"] }

      def assigned!(member)
        raise ReferenceError.new("User is not assigned to this card", code: "not_found", status: 1) unless member["membershipId"]

        member
      end

      def validate_membership!(record, card_id:, user_id: nil, membership_id: nil)
        unless record.is_a?(Hash) && Records.id?(record["id"]) && record["cardId"] == card_id && Records.id?(record["userId"]) &&
               (!user_id || record["userId"] == user_id) && (!membership_id || record["id"] == membership_id) &&
               %w[createdAt updatedAt].all? { |key| record[key].nil? || record[key].is_a?(String) }
          raise InvalidResponse, "Invalid membership"
        end
      end

      def member_data(user, card_id, membership = nil)
        user.slice("id", "name").merge("username" => user["username"], "cardId" => card_id,
                                       "membershipId" => membership&.fetch("id"), "createdAt" => membership&.[]("createdAt"),
                                       "updatedAt" => membership&.[]("updatedAt"))
      end

      def collection(data, name:, limit:)
        data = data.select { |member| member["name"] == name } if name
        data = data.sort_by { |member| member["membershipId"].to_i }
        CollectionResult.new(data: limit ? data.first(limit) : data, complete: !limit || data.size <= limit)
      end

      def mutate(reference, assigned:)
        known = observe_member(reference)
        if assigned == !known["membershipId"].nil?
          return MutationResult.new(data: known.merge("assigned" => assigned), changed: false)
        end

        Write.perform(**write_outcomes(known, assigned)) do
          record = confirmed_write(assigned, known)
          assignment_data(known, record, assigned)
        end
      end

      def confirmed_write(assigned, known)
        card_id, user_id = known.values_at("cardId", "id")
        response = assigned ? @client.add_card_member(card_id, user_id) : @client.remove_card_member(card_id, user_id)
        record = response["item"]
        validate_membership!(record, card_id: card_id, user_id: user_id, membership_id: known["membershipId"])
        record
      end

      def assignment_data(known, record, assigned)
        data = assigned ? member_data(known, known["cardId"], record) : known
        data.merge("assigned" => assigned)
      end

      def write_outcomes(known, assigned)
        { unchanged: known.merge("assigned" => !assigned), unknown: known.merge("assigned" => nil),
          recovery: { "action" => "readback-membership", "resources" => [{ "type" => "card", "id" => known["cardId"] },
                                                                         { "type" => "user", "id" => known["id"] }] } }
      end
    end
  end
end
