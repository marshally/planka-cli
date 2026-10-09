module Planka
  module Boards
    # Reads and changes native cards. An explicit card or list ID determines its
    # own board; names resolve within the asserted board. Each operation observes
    # current server state through the supplied authenticated client.
    class Cards < Resource
      def initialize(client, board_id: nil)
        super(client)
        @board_id = board_id
        @scope = CardScope.new(client, board_id: board_id)
      end

      # Every card in the board's active/closed lists, or in one of them,
      # matching all filters. Archive/trash cards are not read. Lists keep board
      # order; cards keep position order.
      def all(list: nil, name: nil, labels: [], members: [], limit: nil)
        validate_options!(name: name, labels: labels, members: members, limit: limit)
        collect(limit) do |data|
          board = @scope.board(list)
          wanted = filters(board, labels: labels, members: members)
          readable_lists(board, list).each { |record| collect_list!(data, board, record, name, wanted) }
        end
      end

      def find(reference) = read_record(reference).card

      # Creates a native card in LIST, appending unless a position is given.
      # Type defaults to the board's type unless explicitly supplied.
      # Archive/trash lists take no position. No workflow records are added.
      def create(list, name:, description: nil, position: nil, type: nil) = super

      # Changes only the supplied name and/or description.
      def update(reference, name: nil, description: nil) = super(reference, **{ name: name, description: description }.compact)

      # Moves the card to LIST on its own board; see CardMove.
      def move(reference, list:, position: nil) = CardMove.new(client, list: list, board_id: @board_id).move(reference, position: position)

      # Issues one native card deletion; Planka removes the card's own records
      # and clears other tasks' links to it without deleting those cards.
      public :delete

      private

      def validate_options!(name:, labels:, members:, limit:)
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "labels and members must be arrays" unless labels.is_a?(Array) && members.is_a?(Array)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def readable_lists(board, list)
        lists = @scope.lists(board, list).select { |record| @scope.finite?(record) }
        raise ReferenceError, "get cards reads active and closed lists only, not archive and trash lists" if list && lists.empty?

        lists
      end

      def filters(board, labels:, members:)
        { "labelId" => resolve_ids(board_labels(board), labels, "label"), "userId" => resolve_ids(board_users(board), members, "user") }
      end

      def resolve_ids(records, references, resource)
        references.map { |reference| Reference.resolve(records, reference, resource: resource).fetch("id") }.uniq
      end

      def board_labels(board)
        labels = board["included"]["labels"]
        unless labels.is_a?(Array) && labels.all? { |label| label.is_a?(Hash) && Records.id?(label["id"]) && (label["name"].nil? || label["name"].is_a?(String)) }
          raise InvalidResponse, "Invalid board labels"
        end

        labels
      end

      # Users holding a board membership, who are the only possible card members.
      def board_users(board)
        users, memberships = board["included"].values_at("users", "boardMemberships")
        unless users.is_a?(Array) && users.all? { |user| user.is_a?(Hash) && Records.id?(user["id"]) && user["name"].is_a?(String) } &&
               memberships.is_a?(Array) && memberships.all? { |member| member.is_a?(Hash) && Records.id?(member["userId"]) }
          raise InvalidResponse, "Invalid board members"
        end

        users.select { |user| memberships.any? { |member| member["userId"] == user["id"] } }
      end

      def collect_list!(data, board, list, name, wanted)
        relations = relation_index(board["included"])
        @scope.list_cards(board, list).sort_by { |card| [card["position"].to_f, card["id"].to_i] }.each do |card|
          related = relations.transform_values { |ids| ids.fetch(card["id"], []) }
          data << CardRecord.data(card) if (name.nil? || card["name"] == name) && wanted.all? { |key, ids| (ids - related[key]).empty? }
        end
      end

      # Card label and member IDs by card ID, from the board's included records.
      def relation_index(included)
        { "labelId" => "cardLabels", "userId" => "cardMemberships" }.to_h do |key, collection|
          records = included[collection]
          unless records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) && Records.id?(record["cardId"]) && Records.id?(record[key]) }
            raise InvalidResponse, "Invalid card relations"
          end

          [key, records.group_by { |record| record["cardId"] }.transform_values { |group| group.map { |record| record[key] } }]
        end
      end

      def read_record(reference) = CardScope::Observation.new(card: @scope.card(reference), destination: nil)

      def read_creation_scope(list) = @scope.creation(list)

      def record_data(known) = known.card

      def unconfirmed_data(known, desired, returned)
        data = super
        known.card["id"] ? data : data.merge("id" => CardRecord.created_id(returned, known.existing_ids))
      end

      def unconfirmed_recovery(known, desired, returned) = CardRecord.recovery(unconfirmed_data(known, desired, returned))

      def creation_attributes(name:, description:, position:, type:)
        { "name" => CardRecord.text!("name", name, CardRecord::NAME_LIMIT),
          "description" => description && CardRecord.text!("description", description, CardRecord::DESCRIPTION_LIMIT),
          "position" => CardRecord.position!(position), "type" => type && CardRecord.type!(type) }
      end

      def creation_data(known, attributes)
        destination = known.destination
        known.card.merge(attributes.slice("name", "description"), "type" => creation_type(known, attributes),
                                                                  "position" => destination.position(attributes["position"]))
      end

      # Creation owns type selection; the destination supplies the board default
      # independently of its placement rule.
      def creation_type(known, attributes) = attributes["type"] || known.destination.default_card_type

      def create_record(_known, desired)
        request = { type: desired["type"], name: desired["name"], position: desired["position"], description: desired["description"] }
        client.create_card(desired["listId"], **request.compact)
      end

      def update_attributes(**attributes)
        raise ArgumentError, "supply a name or description" if attributes.empty?

        limits = { name: CardRecord::NAME_LIMIT, description: CardRecord::DESCRIPTION_LIMIT }
        attributes.to_h { |field, value| [field.to_s, CardRecord.text!(field, value, limits.fetch(field))] }
      end

      # Only supplied fields whose values differ are sent.
      def update_record(known, desired)
        changed = desired.slice("name", "description").reject { |field, value| known.card[field] == value }
        client.update_card(known.card["id"], **changed.transform_keys(&:to_sym))
      end

      def deletion_data(known) = known.card.merge("deleted" => true)
      def delete_record(known) = client.delete_card(known.card["id"])

      def validate_record!(record, desired, observation:)
        if observation.card["id"].nil? && !CardRecord.created_id(record, observation.existing_ids)
          raise InvalidResponse, "Creation did not return a new card ID"
        end

        CardRecord.confirm!(record, desired)
      end

      def confirmed_data(record, desired) = CardRecord.data(record).merge(desired.slice("deleted"))
      def recovery(known) = CardRecord.recovery(known.card)
    end
  end
end
