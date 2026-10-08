module Planka
  module Cards
    # Native comments, scoped to a card because there is no individual GET.
    class Comments < Resource
      PAGE_SIZE = 50

      def initialize(client, card_id:, board_id: nil)
        super(client)
        @card_id, @board_id = card_id, board_id
      end

      def all(limit: nil)
        validate_limit!(limit)
        collect(limit) do |data|
          each_comment { |comment| data << comment }
        end
      end

      def find(reference) = read_record(reference)

      def create(text:) = super(@card_id, text: text)
      public :update, :delete

      private

      def validate_limit!(limit)
        return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

        raise ArgumentError, "limit must be a positive integer"
      end

      def creation_attributes(text:) = { "text" => CommentRecord.text!(text) }
      def update_attributes(text:) = { "text" => CommentRecord.text!(text) }
      def update_record(known, desired) = client.update_comment(known["id"], text: desired["text"])
      def deletion_data(known) = known.merge("deleted" => true)
      def delete_record(known) = client.delete_comment(known["id"])

      def read_creation_scope(_reference)
        CommentRecord.placeholder(read_card_id)
      end

      def creation_data(known, attributes) = known.merge(attributes)
      def create_record(_known, desired) = client.create_comment(desired["cardId"], text: desired["text"])
      def validate_record!(record, desired, **) = CommentRecord.confirm!(record, desired)
      def confirmed_data(record, desired) = CommentRecord.data(record).merge(desired.slice("deleted"))
      def recovery(known) = CommentRecord.recovery(known)

      def unconfirmed_data(known, desired, returned)
        data = super
        known["id"] ? data : data.merge("id" => CommentRecord.returned_id(returned, known["cardId"]))
      end

      def unconfirmed_recovery(known, desired, returned) = CommentRecord.recovery(unconfirmed_data(known, desired, returned))

      def read_record(reference)
        raise ArgumentError, "comment must be a numeric ID" unless Records.id?(reference)

        each_comment { |comment| return comment if comment["id"] == reference }
        raise ReferenceError.new("Comment not found on --card", code: "not_found", status: 1)
      end

      def each_comment
        card_id = read_card_id
        before_id = nil
        loop do
          page = read_page(card_id, before_id: before_id)
          page.each do |record|
            comment = verified_comment(record, card_id: card_id, before_id: before_id)
            yield comment
            before_id = comment["id"]
          end
          break if page.size < PAGE_SIZE
        end
      end

      def read_card_id
        card = Scope.card(client, card_id: @card_id, board_id: @board_id)
        Scope.card_id(card)
      end

      def read_page(card_id, before_id:)
        page = client.comments_page(card_id, before_id: before_id)
        raise InvalidResponse, "Invalid comment page" unless page.is_a?(Array) && page.size <= PAGE_SIZE

        page
      end

      def verified_comment(record, card_id:, before_id:)
        comment = CommentRecord.data(record)
        unless comment["cardId"] == card_id && (!before_id || comment["id"].to_i < before_id.to_i)
          raise InvalidResponse, "Invalid comment scope or order"
        end

        comment
      end
    end
  end
end
