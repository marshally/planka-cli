module Planka
  module Workflow
    module Resume
      # Fills an existing ticket's missing acceptance criteria; each write confirms
      # its own response. It never creates a card.
      class Ticket
        def self.read(client, id, criteria:, base_url:)
          progress = Progress.new(id, base_url: base_url)
          Criteria::Fill.call(client, id, criteria: criteria, progress: progress)
        end
      end
    end
  end
end
