module Planka
  module Workflow
    # Preserves the legacy claim operation's membership-then-move sequence.
    module Claim
      Result = Data.define(:data, :card)

      def self.call(client, id, base_url:)
        me = client.me.fetch("id")
        included = client.board(client.card(id).dig("item", "boardId"))
        in_progress = included.fetch("lists").find { |list| list["name"] == Card::IN_PROGRESS_LIST } or raise Planka::Error, "no in-progress list"
        member = included.fetch("cardMemberships").any? { |record| record["cardId"] == id && record["userId"] == me }

        client.add_card_member(id, me) unless member
        moved = client.move_card(id, in_progress.fetch("id"))
        card = Planka::Board.new(included, base_url: base_url).card(id)
        data = {
          "card" => moved.slice("id", "name", "listId", "position").merge("url" => card.url),
          "claimed" => true,
          "memberAdded" => !member,
        }
        Result.new(data: data, card: card)
      end
    end
  end
end
