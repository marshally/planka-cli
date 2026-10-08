module Planka
  # Failures an operation reports as known results: Planka errors and failures
  # to reach Planka. Programming errors propagate unchanged.
  OPERATION_ERRORS = [Error, *Client::NETWORK_ERRORS].freeze

  # Runs one resource write. The block returns result data only after confirming
  # the response; reads and no-op checks belong before this boundary.
  module Write
    def self.perform(unchanged:, unknown:, recovery:)
      MutationResult.new(data: yield, changed: true)
    rescue *OPERATION_ERRORS => error
      uncertain = !Client.unapplied?(error)
      raise MutationFailure.new(data: uncertain ? resolve(unknown) : unchanged,
                                changed: uncertain ? nil : false, uncertain: uncertain,
                                recovery: resolve(recovery))
    end

    # Deferred projections may incorporate an identity returned by a malformed
    # response. Classification and failure construction still belong here.
    def self.resolve(projection) = projection.respond_to?(:call) ? projection.call : projection
    private_class_method :resolve
  end
end
