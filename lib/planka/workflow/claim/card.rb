module Planka
  module Workflow
    module Claim
      # Coordinates membership before placement; each step confirms its own response.
      class Card
        def self.read(client, id, base_url:)
          new(client, id, base_url).call
        end

        def initialize(client, id, base_url)
          @client, @id = client, id
          @progress = Progress.new(id, base_url: base_url)
        end

        def call
          scope = Scope.read(@client, @id)
          @progress.start(scope)
          ensure_membership(scope)
          ensure_in_progress(scope)
          @progress.result
        rescue Planka::Error, *Client::NETWORK_ERRORS => error
          raise @progress.failure(error)
        end

        private

        def ensure_membership(scope)
          return if scope.claimed?
          @progress.add_member do
            scope.created_membership(@client.add_card_member(@id, scope.user_id))
          end
        end

        def ensure_in_progress(scope)
          return if scope.in_progress?
          @progress.move do
            scope.moved_card(@client.move_card(@id, scope.in_progress_list_id, position: Position::MOVE_DEFAULT, idempotent: false))
          end
        end
      end
    end
  end
end
