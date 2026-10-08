module Planka
  module Cards
    # Reads and changes native card task lists. An explicit task-list ID
    # determines its own card; names resolve within the asserted card. Each
    # operation observes current server state through the supplied client.
    class TaskLists < Resource
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      # A task list's public data with the position that appends a new one.
      Observation = Data.define(:task_list, :append_position)

      def initialize(client, card_id: nil, board_id: nil)
        super(client)
        @card_id = card_id
        @scope = TaskListScope.new(client, card_id: card_id, board_id: board_id)
      end

      # Every task list on the card, in card order, matching an exact name.
      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)
        data = []
        @scope.task_lists(@scope.card(nil)).each { |record| data << TaskListRecord.data(record) if name.nil? || record["name"] == name }
        CollectionResult.limited(data, limit)
      rescue *OPERATION_ERRORS => error
        raise if error.is_a?(ReferenceError)

        raise CollectionFailure.new(data: CollectionResult.limited(data, limit).data)
      end

      def find(reference) = read_record(reference).task_list

      # Creates a task list on the card, appending after its task lists unless
      # a position is given. Planka's own display defaults apply.
      def create(name:, position: nil)
        raise ArgumentError, "task lists are created on a card" unless @card_id

        super(@card_id, name: name, position: position)
      end

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "task lists are read from a card" unless @card_id
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def read_record(reference)
        Observation.new(task_list: TaskListRecord.data(@scope.task_lists(@scope.card(reference), reference).first), append_position: nil)
      end

      # The card ID is the one this resource was constructed with.
      def read_creation_scope(_card_id)
        card = @scope.card(nil)
        Observation.new(task_list: TaskListRecord.placeholder(Scope.card_id(card)), append_position: Position.after(@scope.task_lists(card)))
      end

      def record_data(known) = known.task_list

      def creation_attributes(name:, position:)
        { "name" => TaskListRecord.name!(name), "position" => position && TaskListRecord.position!(position) }
      end

      def creation_data(known, attributes) = known.task_list.merge(attributes, "position" => attributes["position"] || known.append_position)
      def create_record(_known, desired) = client.create_task_list(desired["cardId"], name: desired["name"], position: desired["position"])

      def validate_record!(record, desired) = TaskListRecord.confirm!(record, desired)
      def confirmed_data(record, _desired) = TaskListRecord.data(record)
      def recovery(known) = TaskListRecord.recovery(known.task_list)
    end
  end
end
