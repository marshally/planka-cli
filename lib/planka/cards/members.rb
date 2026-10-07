module Planka
  module Cards
    # Reads and changes assignments within one card scope. Each operation observes
    # current state through the supplied authenticated client.
    class Members < Resource
      include Relationship

      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def initialize(client, card_id:, board_id: nil)
        super(client)
        @card_id, @board_id = card_id, board_id
      end

      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)
        data = []
        card, board = Scope.read(client, card_id: @card_id, board_id: @board_id)
        hydrate_members!(data, card, identities(board), Scope.card_id(card))
        collection(data, name: name, limit: limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: collection(data, name: name, limit: limit).data)
      end

      def find(reference) = assigned!(read_record(reference))

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference)
        card, board = Scope.read(client, card_id: @card_id, board_id: @board_id)
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

      def relationship_present?(known) = !known["membershipId"].nil?
      def relationship_data(known, present:) = known.merge("assigned" => present)

      def create_record(known, _desired) = client.add_card_member(known["cardId"], known["id"])["item"]
      def delete_record(known) = client.remove_card_member(known["cardId"], known["id"])["item"]

      def validate_record!(record, desired)
        validate_membership!(record, card_id: desired["cardId"], user_id: desired["id"], membership_id: desired["membershipId"])
      end

      def confirmed_data(record, desired)
        return desired unless desired["assigned"]

        member_data(desired, desired["cardId"], record).merge("assigned" => true)
      end

      def recovery(known)
        { "action" => "readback-membership", "resources" => [{ "type" => "card", "id" => known["cardId"] },
                                                             { "type" => "user", "id" => known["id"] }] }
      end
    end
  end
end
