require "planka/workflow"

module Planka
  # Legacy environment defaults stay in this compatibility adapter.
  class Publishing < Workflow::Publishing
    def initialize(client, base_url: ENV.fetch("PLANKA_BASE_URL"))
      super(client, base_url: base_url)
    end
  end
end
