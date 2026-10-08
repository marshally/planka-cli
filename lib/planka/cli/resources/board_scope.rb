require "planka"
require "planka/cli/failure"
require "planka/cli/instance"

module Planka
  module CLI
    module Resources
      # Board scope for references to board-owned resources: an explicit --board
      # always asserts the parent; names fall back to PLANKA_BOARD_ID; IDs and
      # URLs need no board.
      module BoardScope
        def self.for_reference(env, instance, reference, board, resource:)
          return resolve(instance, board) if board

          default(env, instance, resource: resource) unless Records.id?(reference)
        end

        def self.resolve(instance, board) = instance.resolve(board, resource: "board", collection: "boards")

        def self.default(env, instance, resource:)
          board = env["PLANKA_BOARD_ID"]
          if board.nil? || board.empty?
            raise Failure.invalid_input("#{resource} names require --board or PLANKA_BOARD_ID")
          end

          resolve(instance, board)
        rescue Instance::InvalidReference
          raise Failure.configuration("PLANKA_BOARD_ID must be a board ID or same-instance URL")
        end
      end
    end
  end
end
