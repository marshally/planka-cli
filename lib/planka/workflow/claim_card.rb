module Planka
  module Workflow
    # Coordinates membership before placement; each step confirms its own response.
    class ClaimCard
      POSITION = 65_535

      def self.read(client, id, base_url:)
        new(client, id, base_url).call
      end

      def initialize(client, id, base_url)
        @client, @id = client, id
        @progress = ClaimProgress.new(id, base_url: base_url)
      end

      def call
        scope = ClaimScope.read(@client, @id)
        @progress.start(scope)
        ensure_membership(scope)
        ensure_in_progress(scope)
        @progress.result
      rescue Planka::Error, SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError => error
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
          scope.moved_card(@client.move_card(@id, scope.in_progress_list_id, position: POSITION, idempotent: false))
        end
      end
    end
  end
end
