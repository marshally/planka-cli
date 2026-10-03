require "planka"

module Planka
  module CLI
    # An expected command failure with safe presentation and known result data.
    class Failure < Planka::Error
      attr_reader :code, :status, :data, :meta, :program, :output

      def initialize(code:, message:, status: 1, data: nil, meta: {}, program: nil, output: nil)
        super(message)
        @code, @status, @data, @meta = code, status, data, meta
        @program, @output = program, output
      end
    end
  end
end
