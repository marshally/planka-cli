module Planka
  module Cards
    # Observes card assignments, then reads or changes one verified relationship.
    class Members
      OPERATION_ERRORS = [Planka::Error, SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError].freeze

      class << self
        def read(client, reference = nil, card_id:, base_url:, board_id: nil, name: nil, limit: nil, operation: nil)
          data = []
          card, board = card_scope(client, card_id: card_id, board_id: board_id)
          card_id = card.fetch("item").fetch("id")
          users = identities(board)
          user = resolve_user(reference, users, board, card.fetch("item").fetch("boardId")) if reference
          hydrate_members!(data, card, users, card_id)
          return collection(data, name: name, limit: limit) unless reference

          member = data.find { |record| record["id"] == user["id"] }
          return mutate(client, operation, user, card_id, member) if operation
          raise ReferenceError.new("User is not assigned to this card", code: "not_found", status: 1) unless member
          member
        rescue *OPERATION_ERRORS => error
          raise if reference || error.is_a?(ReferenceError)
          raise CollectionFailure.new(data: collection(data, name: name, limit: limit).data)
        end

        private

        def card_scope(client, card_id:, board_id:)
          unless id?(card_id)
            board = client.board(board_id)
            card_id = resolve_card_name(card_id, board, board_id)
          end
          card = client.card(card_id)
          item = card["item"]
          unless item.is_a?(Hash) && item["id"] == card_id && id?(item["boardId"])
            raise InvalidResponse, "Invalid member card"
          end
          raise ReferenceError, "Card does not belong to --board" if board_id && board_id != item["boardId"]
          [card, board || client.board(item["boardId"])]
        end

        def resolve_card_name(name, board, board_id)
          cards = board["cards"]
          unless cards.is_a?(Array) && cards.all? { |record| record.is_a?(Hash) && id?(record["id"]) &&
              record["boardId"] == board_id && record["name"].is_a?(String) } &&
              cards.map { |record| record["id"] }.uniq.size == cards.size
            raise InvalidResponse, "Invalid card name scope"
          end
          resolve(cards, name, resource: "card").fetch("id")
        end

        def identities(board)
          users = board["users"]
          unless users.is_a?(Array) && users.all? { |user| user.is_a?(Hash) && id?(user["id"]) &&
              user["name"].is_a?(String) && (user["username"].nil? || user["username"].is_a?(String)) } &&
              users.map { |user| user["id"] }.uniq.size == users.size
            raise InvalidResponse, "Invalid member identities"
          end
          users
        end

        def resolve_user(reference, users, board, board_id)
          members = board["boardMemberships"]
          unless members.is_a?(Array) && members.all? { |member| member.is_a?(Hash) &&
              member["boardId"] == board_id && id?(member["userId"]) }
            raise InvalidResponse, "Invalid board member scope"
          end
          scoped = users.select { |user| members.any? { |member| member["userId"] == user["id"] } }
          resolve(scoped, reference, resource: "user")
        end

        def resolve(records, reference, resource:)
          matches = records.select { |record| id?(reference) ? record["id"] == reference : record["name"] == reference }
          raise ReferenceError.new("#{resource.capitalize} not found on the specified board", code: "not_found", status: 1) if matches.empty?
          if matches.size > 1
            raise ReferenceError, "Ambiguous #{resource} name; candidate IDs: #{matches.map { |record| record['id'] }.join(', ')}"
          end
          matches.first
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

        def validate_membership!(record, card_id:, user_id: nil, membership_id: nil)
          unless record.is_a?(Hash) && id?(record["id"]) && record["cardId"] == card_id && id?(record["userId"]) &&
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

        def mutate(client, operation, user, card_id, member)
          assigned = operation == :add
          known = member || member_data(user, card_id)
          if assigned == !member.nil?
            return MutationResult.new(data: known.merge("assigned" => assigned), changed: false)
          end

          begin
            response = assigned ? client.add_card_member(card_id, user["id"]) : client.remove_card_member(card_id, user["id"])
            record = response["item"]
            validate_membership!(record, card_id: card_id, user_id: user["id"], membership_id: member&.fetch("membershipId"))
            result = assigned ? member_data(user, card_id, record) : known
            MutationResult.new(data: result.merge("assigned" => assigned), changed: true)
          rescue *OPERATION_ERRORS => error
            uncertain = !error.is_a?(Client::HTTPError) && !Client::UNSENT.any? { |klass| error.is_a?(klass) }
            raise MutationFailure.new(data: known.merge("assigned" => uncertain ? nil : !member.nil?),
              changed: uncertain ? nil : false, uncertain: uncertain,
              recovery: { "action" => "readback-membership", "resources" => [{ "type" => "card", "id" => card_id },
                { "type" => "user", "id" => user["id"] }] })
          end
        end

        def id?(value) = value.is_a?(String) && value.match?(/\A\d+\z/)
      end
    end
  end
end
