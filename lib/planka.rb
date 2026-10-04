require "time"

# General Planka resource models and operations.
module Planka
  Error = Class.new(StandardError)
  InvalidResponse = Class.new(Error)
  DependencyUnavailable = Class.new(Error)

  # A multi-step create failed partway through. #state holds the ids created so
  # far so the caller can report them and resume the rest.
  class PartialFailure < Error
    attr_reader :state

    def initialize(message, state)
      super(message)
      @state = state
    end
  end


  # A card id, given as an id or a card URL.
  def self.card_id(arg)
    arg[/(\d+)\/?\z/, 1] or raise Error, "not a card id or URL: #{arg}"
  end
end

require_relative "planka/client"
require_relative "planka/board"
require_relative "planka/card"
require_relative "planka/snapshot"
require_relative "planka/card_detail"
require_relative "planka/labels"
require_relative "planka/lists"
require_relative "planka/task_lists"

require_relative "planka/version"
