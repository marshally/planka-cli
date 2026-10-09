require "planka"
require "planka/cli/failure"
require "planka/cli/input_file"
require "planka/cli/resources/board_scope"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    # Converts canonical card flags into explicit operation inputs before a
    # session opens. Command catalogs own their required flags and diagnostics.
    module CardInput
      def self.creation(env, instance:, flags:)
        list_scope(env, instance: instance, flags: flags).merge(fields(flags), position: position(flags))
      end

      # An explicit --board asserts the list's parent; list names fall back to
      # PLANKA_BOARD_ID; list IDs and URLs find their own board.
      def self.list_scope(env, instance:, flags:)
        board = flags[:board]&.first
        list = flags[:list] && instance.resolve(flags[:list].first, resource: "list", collection: "lists", names: true)
        board_id = if board then Resources::BoardScope.resolve(instance, board)
                   elsif list && !Records.id?(list) then Resources::BoardScope.default(env, instance, resource: "Card")
                   end
        { board_id: board_id, list: list }
      end

      def self.fields(flags) = { name: flags[:name]&.first, description: description(flags) }

      # Validated by error before preparation.
      def self.position(flags) = flags[:position] && Float(flags[:position].first)

      def self.error(flags)
        error = Resources::ScalarFlags.error(flags)
        return error if error
        if flags[:name] && !Planka::Boards::CardRecord.text?(flags[:name].first, Planka::Boards::CardRecord::NAME_LIMIT)
          return "--name must be at most #{Planka::Boards::CardRecord::NAME_LIMIT} characters"
        end

        position = flags[:position] && Float(flags[:position].first, exception: false)
        "--position must be finite and nonnegative" if flags[:position] && !(position&.finite? && position >= 0)
      end

      def self.description(flags)
        path = flags[:description_file]&.first or return
        text = InputFile.read(path)
        return text if Planka::Boards::CardRecord.text?(text, Planka::Boards::CardRecord::DESCRIPTION_LIMIT)

        raise Failure.invalid_input("--description-file must be nonempty UTF-8 text of at most #{Planka::Boards::CardRecord::DESCRIPTION_LIMIT} characters")
      rescue SystemCallError, IOError
        raise Failure.invalid_input("Could not read --description-file")
      end
      private_class_method :description
    end
  end
end
