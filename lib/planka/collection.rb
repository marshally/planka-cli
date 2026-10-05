module Planka
  class ReferenceError < Error
    attr_reader :code, :status

    def initialize(message, code: "invalid_input", status: 2)
      super(message)
      @code, @status = code, status
    end
  end

  CollectionResult = Data.define(:data, :complete)

  class CollectionFailure < Error
    attr_reader :data

    def initialize(data:)
      super("Could not read the complete collection")
      @data = data
    end
  end
end
