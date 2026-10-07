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
      CARD_TYPES = %w[project story].freeze
      NAME_LIMIT = 1024
      DESCRIPTION_LIMIT = 1_048_576
      # A card's public data with the destination it is being created or moved in.
      Observation = Data.define(:card, :destination)
      Destination = Data.define(:list_id, :finite, :append_position, :card_type)

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

      def find(reference) = read_record(reference).card

      # Creates a native card in LIST, appending unless a position is given.
      # Archive/trash lists take no position. No workflow records are added.
      def create(list, name:, description: nil, position: nil) = super

      # Resource's update algorithm, shared by the update and move verbs.
      alias change update
      private :change

      # Changes only the supplied name and/or description.
      def update(reference, name: nil, description: nil)
        raise ArgumentError, "supply a name or description" if name.nil? && description.nil?

        change(reference, **{ name: name, description: description }.compact)
      end

      # Moves the card to LIST on its own board, appending unless positioned.
      # Its current list without a position is already satisfied.
      def move(reference, list:, position: nil) = change(reference, list: list, position: position)

      # Issues one native card deletion; Planka removes the card's own records
      # and clears other tasks' links to it without deleting those cards.
      public :delete

      # Validates text the way Planka does: lengths count UTF-16 code units.
      def self.text?(value, limit) = value.is_a?(String) && !value.empty? && value.encode("UTF-16LE").bytesize / 2 <= limit

      private

      def creation_attributes(name:, description:, position:)
        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} characters" unless self.class.text?(name, NAME_LIMIT)
        unless description.nil? || self.class.text?(description, DESCRIPTION_LIMIT)
          raise ArgumentError, "description must be nonempty and at most #{DESCRIPTION_LIMIT} characters"
        end

        { "name" => name, "description" => description, "position" => validated_position(position) }
      end

      def validated_position(position)
        return position if position.nil? || (position.is_a?(Numeric) && position.finite? && position >= 0)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def update_attributes(**attributes)
        return move_attributes(**attributes) if attributes.key?(:list)

        attributes.to_h do |key, value|
          limit = { name: NAME_LIMIT, description: DESCRIPTION_LIMIT }.fetch(key)
          raise ArgumentError, "#{key} must be nonempty and at most #{limit} characters" unless self.class.text?(value, limit)

          [key.to_s, value]
        end
      end

      def move_attributes(list:, position:)
        raise ArgumentError, "list must be a nonempty reference" unless list.is_a?(String) && !list.strip.empty?

        { "list" => list, "position" => validated_position(position) }
      end

      def updated_data(known, attributes)
        return super unless attributes.key?("list")

        card = known.card
        destination, = destination(attributes["list"], board_id: card["boardId"], excluding: card["id"], scope: "the card's board")
        card.merge("listId" => destination.list_id, "position" => moved_position(card, destination, attributes["position"]))
      end

      def moved_position(card, destination, requested)
        return card["position"] if requested.nil? && destination.finite && card["listId"] == destination.list_id

        position(destination, requested)
      end

      # Only changed fields are sent; a list change always carries its position.
      def update_record(known, desired)
        changed = desired.reject { |field, value| known.card[field] == value }
        changed = changed.merge(desired.slice("position")) if changed.key?("listId")
        client.update_card(known.card["id"], **changed.slice("name", "description", "listId", "position").transform_keys(&:to_sym))
      end

      def read_creation_scope(list)
        destination, board_id = destination(list)
        Observation.new(card: FIELDS.to_h { |field| [field, nil] }.merge("boardId" => board_id, "listId" => destination.list_id),
                        destination: destination)
      end

      def record_data(known) = known.card

      def creation_data(known, attributes)
        known.card.merge(attributes.slice("name", "description"), "type" => known.destination.card_type,
                                                                  "position" => position(known.destination, attributes["position"]))
      end

      def position(destination, requested)
        return requested || destination.append_position if destination.finite
        raise ReferenceError, "Archive and trash lists do not accept --position" if requested
      end

      def create_record(_known, desired)
        request = { type: desired["type"], name: desired["name"], position: desired["position"], description: desired["description"] }
        client.create_card(desired["listId"], **request.compact)
      end

      # The created or updated card is the requested one; Planka may normalize
      # finite positions, so only their presence is checked.
      def validate_record!(record, desired)
        unless card?(record) && (desired["id"].nil? || record["id"] == desired["id"]) &&
               %w[boardId listId name description type].all? { |field| record[field] == desired[field] } &&
               record["position"].nil? == desired["position"].nil?
          raise InvalidResponse, "Invalid card write response"
        end
      end

      def deletion_data(known) = known.card.merge("deleted" => true)
      def delete_record(known) = client.delete_card(known.card["id"])
      def confirmed_data(record, desired) = card_data(record).merge(desired.slice("deleted"))

      def recovery(known)
        card = known.card
        return { "action" => "readback-card", "resources" => [{ "type" => "card", "id" => card["id"] }] } if card["id"]

        { "action" => "readback-cards", "resources" => [{ "type" => "list", "id" => card["listId"] }] }
      end

      # The verified destination list and the position that appends to it.
      def destination(list, board_id: @board_id, excluding: nil, scope: "--board")
        board = scoped_board(list, board_id)
        record = scoped_lists(board, list, scope: scope).first
        finite = FINITE_LIST_TYPES.include?(record["type"])
        [Destination.new(list_id: record["id"], finite: finite, card_type: card_type(board),
                         append_position: (Position.after(list_cards(board, record, excluding)) if finite)),
         board["item"]["id"]]
      end

      def list_cards(board, list, excluding)
        cards = board["included"]["cards"]
        raise InvalidResponse, "Invalid board cards" unless cards.is_a?(Array) && cards.all?(Hash)

        cards.select { |card| card["listId"] == list["id"] && card["id"] != excluding }.each { |card| scoped_card(card, list) }
      end

      def card_type(board)
        type = board["item"]["defaultCardType"]
        raise InvalidResponse, "Invalid board default card type" unless CARD_TYPES.include?(type)

        type
      end

      def validate_options!(name:, labels:, members:, limit:)
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "labels and members must be arrays" unless labels.is_a?(Array) && members.is_a?(Array)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference)
        Observation.new(card: card_data(Planka::Cards::Scope.card(client, card_id: reference, board_id: @board_id).fetch("item")),
                        destination: nil)
      end

      # The asserted board, or the board an explicit list ID belongs to.
      def scoped_board(list, board_id = @board_id)
        board_id ||= list_board(list)
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

      def scoped_lists(board, list, scope: "--board")
        lists = board_lists(board)
        return lists unless list

        if Records.id?(list) && lists.none? { |record| record["id"] == list }
          raise ReferenceError, "List does not belong to #{scope}"
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
