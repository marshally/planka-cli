module Planka
  module Boards
    # Native labels are read from the complete board snapshot.
    class Labels < Resource
      Observation = Data.define(:label, :append_position, :existing_ids)

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

      def find(reference) = read_record(reference).label

      def create(name:, color:, position: nil) = super(@board_id, name: name, color: color, position: position)

      public :update, :delete

      private

      def deletion_data(known) = known.label.merge("deleted" => true)
      def delete_record(known) = client.delete_label(known.label["id"])

      def update_attributes(**attributes)
        raise ArgumentError, "supply a name, color, or position" if attributes.empty?

        rules = { name: LabelRecord.method(:name!), color: LabelRecord.method(:color!), position: LabelRecord.method(:position!) }
        attributes.to_h { |field, value| [field.to_s, rules.fetch(field) { raise ArgumentError, "unknown label field #{field}" }.call(value)] }
      end

      def creation_attributes(name:, color:, position:)
        { name: LabelRecord.name!(name), color: LabelRecord.color!(color), position: position && LabelRecord.position!(position) }
      end

      def update_record(known, desired)
        changed = desired.slice("name", "color", "position").reject { |field, value| known.label[field] == value }
        client.update_label(known.label["id"], **changed.transform_keys(&:to_sym))
      end

      def read_creation_scope(_board_id)
        labels = each_label.to_a
        Observation.new(label: LabelRecord.placeholder(@board_id), append_position: Position.after(labels), existing_ids: labels.map { |label| label["id"] })
      end

      def record_data(known) = known.label
      def creation_data(known, attributes) = known.label.merge(attributes.transform_keys(&:to_s), "position" => attributes[:position] || known.append_position)
      def create_record(_known, desired) = client.create_label(@board_id, **desired.slice("name", "color", "position").transform_keys(&:to_sym))

      def validate_record!(record, desired, observation:)
        LabelRecord.confirm_new_identity!(record, observation.existing_ids) unless observation.label["id"]
        LabelRecord.confirm!(record, desired)
      end

      def confirmed_data(record, desired) = LabelRecord.data(record).merge(desired.slice("deleted"))
      def recovery(known) = LabelRecord.recovery(known.label)

      def unconfirmed_data(known, desired, returned)
        data = super
        return data if known.label["id"]

        data.merge("id" => LabelRecord.created_id(returned, known.existing_ids))
      end

      def unconfirmed_recovery(known, desired, returned) = LabelRecord.recovery(unconfirmed_data(known, desired, returned))

      def read_record(reference)
        labels = each_label.to_a
        Observation.new(label: Reference.resolve(labels, reference, resource: "label", scope: "the board"), append_position: nil, existing_ids: [])
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
