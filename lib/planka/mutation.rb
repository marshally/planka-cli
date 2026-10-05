module Planka
  # A mutation's known effects are separate from whether the operation completed.
  MutationResult = Data.define(:data, :changed)

  class MutationFailure < Error
    attr_reader :data, :changed, :uncertain, :recovery

    def initialize(data:, changed:, uncertain:, recovery:)
      super("Mutation did not complete")
      @data, @changed, @uncertain, @recovery = data, changed, uncertain, recovery
    end
  end
end
