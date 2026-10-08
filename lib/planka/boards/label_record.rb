module Planka
  module Boards
    # The public fields of a native board label.
    module LabelRecord
      # A returned creation ID can aid readback even when its fields are invalid.
      class UnconfirmedCreation < InvalidResponse
        attr_reader :label_id

        def initialize(label_id)
          super("Invalid created label")
          @label_id = label_id
        end
      end

      NAME_LIMIT = 128
      FIELDS = %w[id boardId name color position createdAt updatedAt].freeze

      COLORS = %w[muddy-grey autumn-leafs morning-sky antique-blue egg-yellow desert-sand dark-granite fresh-salad lagoon-blue midnight-blue light-orange pumpkin-orange light-concrete sunny-grass navy-blue lilac-eyes apricot-red orange-peel silver-glint bright-moss deep-ocean summer-sky berry-red light-cocoa grey-stone tank-green coral-green sugar-plum pink-tulip shady-rust wet-rock wet-moss turquoise-sea lavender-fields piggy-red light-mud gun-metal modern-green french-coast sweet-lilac red-burgundy pirate-gold].freeze

      def self.name!(name)
        return name if Records.text?(name, NAME_LIMIT) && !name.strip.empty?

        raise ArgumentError, "name must be nonempty and at most #{NAME_LIMIT} UTF-16 units"
      end

      def self.color!(color)
        return color if COLORS.include?(color)

        raise ArgumentError, "color must be a native Planka label color"
      end

      def self.position!(position)
        return position if Records.position?(position)

        raise ArgumentError, "position must be finite and nonnegative"
      end

      def self.data(record)
        raise InvalidResponse, "Invalid label record" unless valid?(record)

        FIELDS.to_h { |field| [field, record[field]] }
      end

      def self.placeholder(board_id) = FIELDS.to_h { |field| [field, nil] }.merge("boardId" => board_id)

      def self.confirm!(record, desired)
        unless valid?(record) && (desired["id"].nil? || desired["id"] == record["id"]) &&
               %w[boardId name color].all? { |field| record[field] == desired[field] }
          raise InvalidResponse, "Invalid label write response"
        end
      end

      def self.confirm_creation!(record, desired, existing_ids)
        id = record["id"] if record.is_a?(Hash) && Records.id?(record["id"]) && !existing_ids.include?(record["id"])
        raise InvalidResponse, "Creation returned an existing label" unless id

        confirm!(record, desired)
        record
      rescue InvalidResponse
        raise UnconfirmedCreation, id
      end

      def self.recovery(label)
        resources = [{ "type" => "board", "id" => label["boardId"] }]
        resources << { "type" => "label", "id" => label["id"] } if label["id"]
        { "action" => label["id"] ? "readback-label" : "readback-labels", "resources" => resources }
      end

      def self.valid?(record)
        record.is_a?(Hash) && Records.id?(record["id"]) && Records.id?(record["boardId"]) &&
          (record["name"].nil? || record["name"].is_a?(String)) && COLORS.include?(record["color"]) &&
          Records.position?(record["position"]) &&
          %w[createdAt updatedAt].all? { |field| record[field].nil? || Records.timestamp?(record[field]) }
      end
    end
  end
end
