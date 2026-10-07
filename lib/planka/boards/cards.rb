module Planka
  module Boards
    # Reads and changes native cards. An explicit card or list ID determines its
    # own board; names resolve within the asserted board. Each operation observes
    # current server state through the supplied authenticated client.
    class Cards < Resource
      FIELDS = %w[id name description type boardId listId position createdAt updatedAt].freeze
      LIST_TYPES = %w[active closed archive trash].freeze
      FINITE_LIST_TYPES = %w[active closed].freeze
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def initialize(client, board_id: nil)
        super(client)
        @board_id = board_id
      end

      # Every card on the board, or in one of its lists, matching all filters.
      # Active/closed lists come from the board read; archive/trash lists are
      # paged until empty. Lists keep board order; cards keep native list order.
      def all(list: nil, name: nil, labels: [], members: [], limit: nil)
        validate_options!(name: name, labels: labels, members: members, limit: limit)
        data = []
        board = scoped_board(list)
        wanted = { "labelId" => label_ids(board, labels), "userId" => member_ids(board, members) }
        scoped_lists(board, list).each { |record| collect!(data, board, record, name, wanted) }
        collection(data, limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: collection(data, limit).data)
      end

      def find(reference) = read_record(reference)

      private

      def validate_options!(name:, labels:, members:, limit:)
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "labels and members must be arrays" unless labels.is_a?(Array) && members.is_a?(Array)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference)
        card_data(Planka::Cards::Scope.card(client, card_id: reference, board_id: @board_id).fetch("item"))
      end

      # The asserted board, or the board an explicit list ID belongs to.
      def scoped_board(list)
        board_id = @board_id || list_board(list)
        board = client.board_document(board_id)
        raise InvalidResponse, "Invalid board record" unless board["item"]["id"] == board_id

        board
      end

      def list_board(list)
        raise ArgumentError, "list names require a board" unless Records.id?(list)

        record = client.list(list)
        raise InvalidResponse, "Invalid list record" unless record["id"] == list && Records.id?(record["boardId"])

        record["boardId"]
      end

      def scoped_lists(board, list)
        lists = board_lists(board)
        return lists unless list

        if Records.id?(list) && lists.none? { |record| record["id"] == list }
          raise ReferenceError, "List does not belong to --board"
        end

        [Reference.resolve(lists, list, resource: "list", scope: "the board")]
      end

      def board_lists(board)
        lists = board["included"]["lists"]
        unless lists.is_a?(Array) && lists.all? { |record| list?(record, board["item"]["id"]) }
          raise InvalidResponse, "Invalid board lists"
        end

        lists.sort_by { |record| [FINITE_LIST_TYPES.include?(record["type"]) ? 0 : 1, record["position"].to_f, record["id"].to_i] }
      end

      def list?(record, board_id)
        record.is_a?(Hash) && Records.id?(record["id"]) && record["boardId"] == board_id && LIST_TYPES.include?(record["type"]) &&
          (record["name"].nil? || record["name"].is_a?(String)) && (record["position"].nil? || record["position"].is_a?(Numeric))
      end

      def label_ids(board, references)
        labels = board["included"]["labels"]
        unless labels.is_a?(Array) && labels.all? { |label| label.is_a?(Hash) && Records.id?(label["id"]) && (label["name"].nil? || label["name"].is_a?(String)) }
          raise InvalidResponse, "Invalid board labels"
        end

        references.map { |reference| Reference.resolve(labels, reference, resource: "label").fetch("id") }.uniq
      end

      def member_ids(board, references)
        included = board["included"]
        users, memberships = included.values_at("users", "boardMemberships")
        unless users.is_a?(Array) && users.all? { |user| user.is_a?(Hash) && Records.id?(user["id"]) && user["name"].is_a?(String) } &&
               memberships.is_a?(Array) && memberships.all? { |member| member.is_a?(Hash) && Records.id?(member["userId"]) }
          raise InvalidResponse, "Invalid board members"
        end

        scoped = users.select { |user| memberships.any? { |member| member["userId"] == user["id"] } }
        references.map { |reference| Reference.resolve(scoped, reference, resource: "user").fetch("id") }.uniq
      end

      def collect!(data, board, list, name, wanted)
        each_card(board, list) do |card, relations|
          related = relations.transform_values { |ids| ids.fetch(card["id"], []) }
          data << card_data(card) if (name.nil? || card["name"] == name) && wanted.all? { |key, ids| (ids - related[key]).empty? }
        end
      end

      def each_card(board, list, &)
        return each_paged_card(list, &) unless FINITE_LIST_TYPES.include?(list["type"])

        included = board["included"]
        cards = included["cards"]
        raise InvalidResponse, "Invalid board cards" unless cards.is_a?(Array) && cards.all?(Hash)

        relations = relation_index(included)
        cards.select { |card| card["listId"] == list["id"] }
             .sort_by { |card| [card["position"].to_f, card["id"].to_i] }
             .each { |card| yield scoped_card(card, list), relations }
      end

      # Follows the native listChangedAt/id cursor until a page comes back empty.
      def each_paged_card(list)
        seen, before = [], nil
        loop do
          page = client.list_card_page(list["id"], before: before)
          break if page["items"].empty?

          relations = relation_index(page["included"])
          page["items"].each do |card|
            scoped_card(card, list)
            raise InvalidResponse, "Repeated card in list pages" if seen.include?(card["id"])

            seen << card["id"]
            yield card, relations
          end
          before = cursor(page["items"].last)
        end
      end

      def cursor(card)
        raise InvalidResponse, "Invalid card page cursor" unless Records.timestamp?(card["listChangedAt"])

        card.slice("listChangedAt", "id")
      end

      def scoped_card(card, list)
        card_data(card)
        raise InvalidResponse, "Card outside its list scope" unless card["listId"] == list["id"] && card["boardId"] == list["boardId"]

        card
      end

      # Card label and member IDs by card ID, from one response's included records.
      def relation_index(included)
        { "labelId" => "cardLabels", "userId" => "cardMemberships" }.to_h do |key, collection|
          records = included[collection]
          unless records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) && Records.id?(record["cardId"]) && Records.id?(record[key]) }
            raise InvalidResponse, "Invalid card relations"
          end

          [key, records.group_by { |record| record["cardId"] }.transform_values { |group| group.map { |record| record[key] } }]
        end
      end

      def collection(data, limit) = CollectionResult.new(data: limit ? data.first(limit) : data, complete: !limit || data.size <= limit)

      def card_data(record)
        raise InvalidResponse, "Invalid card record" unless card?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def card?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && record["name"].is_a?(String) &&
          (record["description"].nil? || record["description"].is_a?(String)) && record["type"].is_a?(String) &&
          Records.id?(record["boardId"]) && Records.id?(record["listId"]) &&
          (record["position"].nil? || (record["position"].is_a?(Numeric) && record["position"].finite?)) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
