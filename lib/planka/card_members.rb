module Planka
  # Card membership reads hydrate minimal identities from the card's own board.
  class CardMembers
    def self.read(client, reference = nil, card_id:, base_url:, board_id: nil, name: nil, limit: nil, operation: nil)
      unless id?(card_id)
        board = client.board(board_id)
        cards = board["cards"]
        unless cards.is_a?(Array) && cards.all? { |record| record.is_a?(Hash) && id?(record["id"]) &&
            record["boardId"] == board_id && record["name"].is_a?(String) }
          raise InvalidResponse, "Invalid card name scope"
        end
        candidates = cards.select { |record| record["name"] == card_id }
        raise ReferenceError.new("Card not found on the specified board", code: "not_found", status: 1) if candidates.empty?
        if candidates.size > 1
          raise ReferenceError, "Ambiguous card name; candidate IDs: #{candidates.map { |record| record['id'] }.join(', ')}"
        end
        card_id = candidates.first["id"]
      end
      card = client.card(card_id)
      item = card["item"]
      unless item.is_a?(Hash) && item["id"] == card_id && id?(item["boardId"])
        raise InvalidResponse, "Invalid member card"
      end
      raise ReferenceError, "Card does not belong to --board" if board_id && board_id != item["boardId"]
      board ||= client.board(item["boardId"])
      users = board["users"]
      unless users.is_a?(Array) && users.all? { |user| user.is_a?(Hash) && id?(user["id"]) &&
          user["name"].is_a?(String) && (user["username"].nil? || user["username"].is_a?(String)) } &&
          users.map { |user| user["id"] }.uniq.size == users.size
        raise InvalidResponse, "Invalid member identities"
      end
      if reference
        board_members = board["boardMemberships"]
        unless board_members.is_a?(Array) && board_members.all? { |member| member.is_a?(Hash) &&
            member["boardId"] == item["boardId"] && id?(member["userId"]) }
          raise InvalidResponse, "Invalid board member scope"
        end
        scoped = users.select { |user| board_members.any? { |member| member["userId"] == user["id"] } }
        matches = scoped.select { |user| id?(reference) ? user["id"] == reference : user["name"] == reference }
        if matches.empty?
          raise ReferenceError.new("User not found on the card's board", code: "not_found", status: 1)
        end
        if matches.size > 1
          raise ReferenceError, "Ambiguous user name; candidate IDs: #{matches.map { |user| user['id'] }.join(', ')}"
        end
        user_id = matches.first["id"]
      end
      included = card["included"]
      raise InvalidResponse, "Invalid card relations" unless included.is_a?(Hash)
      records = included["cardMemberships"]
      raise InvalidResponse, "Invalid membership collection" unless records.is_a?(Array)

      data = []
      records.each do |record|
        unless record.is_a?(Hash) && id?(record["id"]) && record["cardId"] == card_id && id?(record["userId"]) &&
            %w[createdAt updatedAt].all? { |key| record[key].nil? || record[key].is_a?(String) }
          raise InvalidResponse, "Invalid membership"
        end
        user = users.find { |identity| identity["id"] == record["userId"] }
        raise InvalidResponse, "Missing member identity" unless user
        raise InvalidResponse, "Duplicate membership" if data.any? { |member| member["id"] == user["id"] || member["membershipId"] == record["id"] }

        data << user.slice("id", "name").merge("username" => user["username"], "cardId" => card_id,
          "membershipId" => record["id"], "createdAt" => record["createdAt"], "updatedAt" => record["updatedAt"])
      end
      if reference
        member = data.find { |record| record["id"] == user_id }
        if operation == :remove
          unless member
            absent = matches.first.slice("id", "name").merge("username" => matches.first["username"], "cardId" => card_id,
              "membershipId" => nil, "createdAt" => nil, "updatedAt" => nil, "assigned" => false)
            return MutationResult.new(data: absent, changed: false)
          end
          pending = true
          response = client.remove_card_member(card_id, user_id)
          record = response["item"]
          unless record.is_a?(Hash) && record["id"] == member["membershipId"] && record["cardId"] == card_id && record["userId"] == user_id
            raise InvalidResponse, "Invalid removed membership"
          end
          return MutationResult.new(data: member.merge("assigned" => false), changed: true)
        end
        if operation == :add
          return MutationResult.new(data: member.merge("assigned" => true), changed: false) if member

          pending = true
          response = client.add_card_member(card_id, user_id)
          record = response["item"]
          unless record.is_a?(Hash) && id?(record["id"]) && record["cardId"] == card_id && record["userId"] == user_id &&
              %w[createdAt updatedAt].all? { |key| record[key].nil? || record[key].is_a?(String) }
            raise InvalidResponse, "Invalid created membership"
          end
          member = matches.first.slice("id", "name").merge("username" => matches.first["username"], "cardId" => card_id,
            "membershipId" => record["id"], "createdAt" => record["createdAt"], "updatedAt" => record["updatedAt"])
          return MutationResult.new(data: member.merge("assigned" => true), changed: true)
        end
        raise ReferenceError.new("User is not assigned to this card", code: "not_found", status: 1) unless member
        member
      else
        data = data.select { |member| member["name"] == name } if name
        data = data.sort_by { |member| member["membershipId"].to_i }
        CollectionResult.new(data: limit ? data.first(limit) : data, complete: !limit || data.size <= limit)
      end
    rescue Planka::Error, SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError => error
      if operation && pending
        uncertain = !error.is_a?(Client::HTTPError) && !Client::UNSENT.any? { |klass| error.is_a?(klass) }
        known = member || matches.first.slice("id", "name").merge("username" => matches.first["username"],
          "cardId" => card_id, "membershipId" => nil, "createdAt" => nil, "updatedAt" => nil)
        raise MutationFailure.new(data: known.merge("assigned" => uncertain ? nil : !member.nil?),
          changed: uncertain ? nil : false, uncertain: uncertain,
          recovery: { "action" => "readback-membership", "resources" => [{ "type" => "card", "id" => card_id },
            { "type" => "user", "id" => user_id }] })
      end
      raise if reference || error.is_a?(ReferenceError)
      raise CollectionFailure.new(data: data || [])
    end

    def self.id?(value) = value.is_a?(String) && value.match?(/\A\d+\z/)
  end
end
