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

      def creation_attributes(name:, type:, position:)
        { "name" => ListRecord.name!(name), "type" => ListRecord.type!(type), "position" => ListRecord.position!(position) }
      end

      def creation_data(known, attributes) = known.list.merge(attributes, "position" => attributes["position"] || known.append_position)

      def create_record(_known, desired)
        client.create_list(desired["boardId"], type: desired["type"], name: desired["name"], position: desired["position"])
      end

      def validate_record!(record, desired) = ListRecord.confirm!(record, desired)
      def confirmed_data(record, _desired) = ListRecord.data(record)
      def recovery(known) = ListRecord.recovery(known.list)
    end
  end
end
