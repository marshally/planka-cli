module Planka
  module Boards
    # Reads and changes native board lists. An explicit list ID determines its
    # own board; names resolve within the asserted board. Each operation observes
    # current server state through the supplied authenticated client.
    class Lists < Resource
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      # A list's public data with the position that appends a new kanban list.
      Observation = Data.define(:list, :append_position)

      def initialize(client, board_id: nil)
        super(client)
        @board_id = board_id
        @scope = ListScope.new(client, board_id: board_id)
      end

      # Every list on the board, of every native type, matching an exact name.
      # Active/closed lists come first by position, then archive and trash.
      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)
        data = []
        @scope.lists(@scope.board(nil)).each { |record| data << ListRecord.data(record) if name.nil? || record["name"] == name }
        CollectionResult.limited(data, limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: CollectionResult.limited(data, limit).data)
      end

      def find(reference) = read_record(reference).list

      # Creates a native kanban list on the board, appending after its active
      # and closed lists unless a position is given.
      def create(name:, type: "active", position: nil) = super(@board_id, name: name, type: type, position: position)

      # Changes only the supplied fields; color: nil clears the color. The list
      # stays on its board, and Planka applies a type change's effects itself.
      def update(reference, **attributes) = super

      # Issues one native list deletion; Planka moves the list's cards to the
      # board's trash list rather than deleting them.
      public :delete

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "lists are read from a board" unless @board_id
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference) = Observation.new(list: ListRecord.data(@scope.lists(@scope.board(reference), reference).first), append_position: nil)

      def read_creation_scope(_board_id)
        board = @scope.board(nil)
        kanban = @scope.lists(board).select { |record| @scope.finite?(record) }
        Observation.new(list: ListRecord.placeholder(board["item"]["id"]), append_position: Position.after(kanban))
      end

      def record_data(known) = known.list

      def update_attributes(**attributes)
        raise ArgumentError, "supply a name, color, position, or type" if attributes.empty?

        rules = { name: ListRecord.method(:name!), color: ListRecord.method(:color!), type: ListRecord.method(:type!),
                  position: ListRecord.method(:position!) }
        attributes.to_h { |field, value| [field.to_s, rules.fetch(field) { raise ArgumentError, "unknown list field #{field}" }.call(value)] }
      end

      def updated_data(known, attributes) = kanban!(known).list.merge(attributes)

      # Only supplied fields whose values differ are sent; a cleared color is null.
      def update_record(known, desired)
        changed = desired.slice("name", "color", "position", "type").reject { |field, value| known.list[field] == value }
        client.update_list(known.list["id"], **changed.transform_keys(&:to_sym))
      end

      def deletion_data(known) = kanban!(known).list.merge("deleted" => true)
      def delete_record(known) = client.delete_list(known.list["id"])

      # Archive and trash are system lists that Planka does not let callers change.
      def kanban!(known)
        return known if @scope.finite?(known.list)

        raise ReferenceError, "Archive and trash lists cannot be updated or deleted"
      end

      def creation_attributes(name:, type:, position:)
        { "name" => ListRecord.name!(name), "type" => ListRecord.type!(type), "position" => position && ListRecord.position!(position) }
      end

      def creation_data(known, attributes) = known.list.merge(attributes, "position" => attributes["position"] || known.append_position)

      def create_record(_known, desired)
        client.create_list(desired["boardId"], type: desired["type"], name: desired["name"], position: desired["position"])
      end

      def validate_record!(record, desired) = ListRecord.confirm!(record, desired)
      def confirmed_data(record, desired) = ListRecord.data(record).merge(desired.slice("deleted"))
      def recovery(known) = ListRecord.recovery(known.list)
    end
  end
end
