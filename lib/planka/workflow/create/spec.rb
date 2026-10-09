module Planka
  module Workflow
    module Create
      # A spec is a project card without an Acceptance criteria list. Core card
      # creation owns scope, placement, response validation, and write recovery.
      module Spec
        def self.create(client, list:, board_id: nil, **attributes)
          Boards::Cards.new(client, board_id: board_id).create(list, **attributes, type: "project")
        end
      end
    end
  end
end
