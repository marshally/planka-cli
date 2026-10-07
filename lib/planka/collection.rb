module Planka
  class ReferenceError < Error
    attr_reader :code, :status

    def initialize(message, code: "invalid_input", status: 2)
      super(message)
      @code, @status = code, status
    end
  end

  CollectionResult = Data.define(:data, :complete) do
    # At most LIMIT matching records; complete unless more records matched.
    def self.limited(data, limit) = new(data: limit ? data.first(limit) : data, complete: !limit || data.size <= limit)
  end

  class CollectionFailure < Error
    attr_reader :data

    def initialize(data:)
      super("Could not read the complete collection")
      @data = data
    end
  end
end
