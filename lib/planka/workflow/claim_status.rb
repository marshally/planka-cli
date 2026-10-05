module Planka
  module Workflow
    # Canonical inspection of the existing Planka-side claim convention.
    module ClaimStatus
      def self.read(client, base_url:)
        LoopLock.report(Reads.new(client), base_url: base_url, exclude_quarantine: true)
      rescue KeyError
        raise InvalidResponse, "Invalid claim-status records"
      end

      # Validates canonical reads while the legacy operation keeps its adapter.
      class Reads
        def initialize(client)
          @client = client
          @comments = HandoffComments.new(client)
        end

        def board_ids = @client.board_ids
        def me = Records.user!(@client.me)
        def comments(id) = @comments.comments(id)

        def board(id)
          included = @client.board(id)
          Boards::Snapshot.validate!(included)
          lists = included.fetch("lists")
          unless lists.all? { |list| Records.id?(list["id"]) && %w[active closed].include?(list["type"]) }
            raise InvalidResponse, "Invalid claim-status lists"
          end
          list_ids = lists.map { |list| list["id"] }
          cards = included.fetch("cards")
          unless cards.all? { |card| Records.id?(card["id"]) && card["name"].is_a?(String) && list_ids.include?(card["listId"]) }
            raise InvalidResponse, "Invalid claim-status cards"
          end
          card_ids = cards.map { |card| card["id"] }
          raise InvalidResponse, "Duplicate claim-status cards" unless card_ids.uniq.size == card_ids.size
          included.fetch("cardMemberships").each do |membership|
            unless card_ids.include?(membership["cardId"]) && membership["userId"].is_a?(String) && !membership["userId"].empty?
              raise InvalidResponse, "Invalid claim-status memberships"
            end
            raise InvalidResponse, "Invalid claim-status timestamp" unless Records.timestamp?(membership["createdAt"])
          end
          included
        end
      end
    end
  end
end
