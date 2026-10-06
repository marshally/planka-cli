module Planka
  class Tasks
    # Task assignment resolves actual board members, independently of card membership.
    module Users
      def self.resolve(client, reference, board_id)
        board = client.board(board_id)
        users, memberships = board.values_at("users", "boardMemberships")
        unless users.is_a?(Array) && users.all? { |user| user.is_a?(Hash) && Records.id?(user["id"]) && user["name"].is_a?(String) } &&
               users.map { |user| user["id"] }.uniq.size == users.size &&
               memberships.is_a?(Array) && memberships.all? { |member|
                 member.is_a?(Hash) && member["boardId"] == board_id && Records.id?(member["userId"]) &&
                 users.any? { |user| user["id"] == member["userId"] }
               }
          raise InvalidResponse, "Invalid task assignee scope"
        end

        members = users.select { |user| memberships.any? { |member| member["userId"] == user["id"] } }
        Reference.resolve(members, reference, resource: "user").fetch("id")
      end
    end
  end
end
