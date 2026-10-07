module Planka
  # Common operation mechanics, not a promise that every resource supports every
  # CRUD verb. Concrete resources expose their supported public operations.
  class Resource
    def initialize(client)
      @client = client
    end

    protected

    attr_reader :client

    # Projections describe the observed, requested, and uncertain public state.
    # Reads and validation happen before entry. The block performs one write and
    # returns confirmed data, including any server-assigned identity or metadata.
    def mutate(unchanged:, desired:, unknown:, recovery:)
      return MutationResult.new(data: desired, changed: false) if unchanged == desired

      Write.perform(unchanged: unchanged, unknown: unknown, recovery: recovery) { yield }
    end
  end
end
