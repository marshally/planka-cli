module Planka
  class Projects < Resource
    # Native boards visible within one explicit project.
    class Boards < Resource
      Observation = Data.define(:board, :append_position, :existing_ids)
      def initialize(client, base_url:, project_id: nil)
        super(client)
        @base_url, @project_id = base_url.sub(%r{/+\z}, ""), project_id
      end

      def create(name:, position: nil)
        raise ArgumentError, "boards are created in a project" unless @project_id

        super(@project_id, name: name, position: position)
      end

      public :update, :delete

      def find(reference) = read_record(reference).board

      def all(name: nil, limit: nil)
        validate_options!(name: name, limit: limit)

        collect(limit, project: ->(data) { data.sort_by { |board| [board["position"], board["id"].to_i] } }) do |data|
          each_board { |board| data << board if name.nil? || board["name"] == name }
        end
      end

      private

      def validate_options!(name:, limit:)
        raise ArgumentError, "boards are read from a project" unless @project_id
        raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
        raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      end

      def creation_attributes(name:, position:)
        { "name" => BoardRecord.name!(name), "position" => position && BoardRecord.position!(position) }
      end

      def read_creation_scope(_project_id)
        boards = each_board.to_a
        Observation.new(board: BoardRecord.placeholder(@project_id), append_position: Position.after(boards), existing_ids: boards.map { |board| board["id"] })
      end

      def record_data(known) = known.board
      def creation_data(known, attributes) = known.board.merge(attributes, "position" => attributes["position"] || known.append_position)
      def create_record(_known, desired) = client.create_board(@project_id, **desired.slice("name", "position").transform_keys(&:to_sym))

      def validate_record!(record, desired, observation:)
        if observation.board["id"].nil? && !BoardRecord.created_id(record, observation.existing_ids)
          raise InvalidResponse, "Creation did not return a new board ID"
        end

        BoardRecord.confirm!(record, desired)
      end

      def confirmed_data(record, desired) = BoardRecord.data(record, base_url: @base_url).merge(desired.slice("deleted"))
      def recovery(known) = BoardRecord.recovery(known.board)
      def deletion_data(known) = known.board.merge("deleted" => true)
      def delete_record(known) = client.delete_board(known.board["id"])

      def unconfirmed_data(known, desired, returned)
        data = super
        return data if known.board["id"]

        id = BoardRecord.created_id(returned, known.existing_ids)
        data.merge("id" => id, "url" => id && "#{@base_url}/boards/#{id}")
      end

      def unconfirmed_recovery(known, desired, returned) = BoardRecord.recovery(unconfirmed_data(known, desired, returned))

      def update_attributes(**attributes)
        raise ArgumentError, "supply a name or position" if attributes.empty?

        rules = { name: BoardRecord.method(:name!), position: BoardRecord.method(:position!) }
        attributes.to_h { |field, value| [field.to_s, rules.fetch(field) { raise ArgumentError, "unknown board field #{field}" }.call(value)] }
      end

      def update_record(known, desired)
        changed = desired.slice("name", "position").reject { |field, value| known.board[field] == value }
        client.update_board(known.board["id"], **changed.transform_keys(&:to_sym))
      end

      def read_record(reference)
        board = Records.id?(reference) ? board_by_id(reference) : named_board(reference)
        Observation.new(board: board, append_position: nil, existing_ids: [])
      end

      def board_by_id(reference)
        board = BoardRecord.data(client.board_document(reference)["item"], base_url: @base_url)
        raise InvalidResponse, "Invalid board identity" unless board["id"] == reference
        raise ReferenceError, "Board does not belong to --project" if @project_id && board["projectId"] != @project_id

        board
      end

      def named_board(reference)
        raise ArgumentError, "board names require a project" unless @project_id

        Reference.resolve(each_board.to_a, reference, resource: "board", scope: "the project")
      rescue ReferenceError => error
        raise ReferenceError.new(error.message, code: error.code, status: 1)
      end

      def each_board
        return enum_for(:each_board) unless block_given?

        seen = {}
        project_boards.each do |record|
          board = BoardRecord.data(record, base_url: @base_url)
          raise InvalidResponse, "Invalid project boards" if board["projectId"] != @project_id || seen[board["id"]]

          seen[board["id"]] = true
          yield board
        end
      end

      def project_boards
        document = client.project_document(@project_id)
        raise InvalidResponse, "Invalid project record" unless document["item"]["id"] == @project_id

        boards = document["included"]["boards"]
        raise InvalidResponse, "Invalid project boards" unless boards.is_a?(Array)

        boards
      end
    end
  end
end
