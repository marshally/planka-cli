module Planka
  module Boards
    # Native labels are read from the complete board snapshot.
    class Labels < Resource
      def initialize(client, board_id:)
        super(client)
        @board_id = board_id
      end

      def all(name: nil, limit: nil)
        collect(limit, project: ->(data) { data.sort_by { |label| [label["position"], label["id"].to_i] } }) do |data|
          each_label do |label|
            data << label if name.nil? || label["name"] == name
          end
        end
      end

      def find(reference) = read_record(reference)

      def create(name:, color:, position: nil)
        super(@board_id, name: name, color: color, position: position)
      rescue MutationFailure => failure
        raise unless failure.cause.is_a?(LabelRecord::UnconfirmedCreation)

        data = failure.data.merge("id" => failure.cause.label_id)
        raise MutationFailure.new(data: data, changed: nil, uncertain: true, recovery: LabelRecord.recovery(data)), cause: failure.cause
      end

      public :update, :delete

      private

      def deletion_data(known) = known.merge("deleted" => true)
      def delete_record(known) = client.delete_label(known["id"])

      def update_attributes(**attributes)
        raise ArgumentError, "supply a name, color, or position" if attributes.empty?

        rules = { name: LabelRecord.method(:name!), color: LabelRecord.method(:color!), position: LabelRecord.method(:position!) }
        attributes.to_h { |field, value| [field.to_s, rules.fetch(field) { raise ArgumentError, "unknown label field #{field}" }.call(value)] }
      end

      def creation_attributes(name:, color:, position:)
        { name: LabelRecord.name!(name), color: LabelRecord.color!(color), position: position && LabelRecord.position!(position) }
      end

      def update_record(known, desired)
        changed = desired.slice("name", "color", "position").reject { |field, value| known[field] == value }
        client.update_label(known["id"], **changed.transform_keys(&:to_sym))
      end

      def read_creation_scope(_board_id)
        labels = each_label.to_a
        { "label" => LabelRecord.placeholder(@board_id), "appendPosition" => Position.after(labels), "existingIds" => labels.map { |label| label["id"] } }
      end

      def record_data(known) = known.fetch("label", known)
      def creation_data(known, attributes) = known["label"].merge(attributes.transform_keys(&:to_s), "position" => attributes[:position] || known["appendPosition"])

      def create_record(known, desired)
        record = client.create_label(@board_id, **desired.slice("name", "color", "position").transform_keys(&:to_sym))
        LabelRecord.confirm_creation!(record, desired, known["existingIds"])
      end

      def validate_record!(record, desired) = (LabelRecord.confirm!(record, desired) if desired["id"])
      def confirmed_data(record, desired) = LabelRecord.data(record).merge(desired.slice("deleted"))
      def recovery(known) = LabelRecord.recovery(record_data(known))

      def read_record(reference)
        labels = each_label.to_a
        Reference.resolve(labels, reference, resource: "label", scope: "the board")
      end

      def each_label
        return enum_for(:each_label) unless block_given?

        seen = {}
        board_labels.each do |record|
          label = LabelRecord.data(record)
          raise InvalidResponse, "Invalid board labels" if label["boardId"] != @board_id || seen[label["id"]]

          seen[label["id"]] = true
          yield label
        end
      end

      def board_labels
        board = client.board_document(@board_id)
        raise InvalidResponse, "Invalid board record" unless board["item"]["id"] == @board_id

        labels = board["included"]["labels"]
        raise InvalidResponse, "Invalid board labels" unless labels.is_a?(Array)

        labels
      end
    end
  end
end
