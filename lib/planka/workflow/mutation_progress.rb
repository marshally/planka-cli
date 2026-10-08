module Planka
  module Workflow
    # Owns write confirmation and common mutation failure accounting.
    class MutationProgress
      def initialize(id)
        @id = id
        @data = nil
        @changed = false
        @pending_step = nil
      end

      def start(scope)
        @data = initial_data(scope)
      end

      # The block validates and projects the response before confirmation; it returns
      # the concrete operation's result after projection.
      private

      def step(step)
        @pending_step = step
        result = yield
        @changed = true
        @pending_step = nil
        result
      end

      public

      def result = MutationResult.new(data: @data, changed: @changed)

      def failure(error)
        uncertain = !@pending_step.nil? && !Client.unapplied?(error)
        record_uncertain_step(@pending_step) if uncertain
        MutationFailure.new(data: @data, changed: @changed ? true : (uncertain ? nil : false),
                            uncertain: uncertain, recovery: recovery)
      end

      private

      def initial_data(_scope) = raise(NotImplementedError)
      def record_uncertain_step(_step) = raise(NotImplementedError)
      def recovery = raise(NotImplementedError)
    end
  end
end
