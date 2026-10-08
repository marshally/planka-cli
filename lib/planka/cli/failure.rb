require "planka"

module Planka
  module CLI
    # An expected command failure with safe presentation and known result data.
    class Failure < Planka::Error
      attr_reader :code, :status, :data, :meta, :program, :output, :recovery

      def initialize(code:, message:, status: 1, data: nil, meta: {}, program: nil, output: nil, recovery: nil)
        super(message)
        @code, @status, @data, @meta = code, status, data, meta
        @program, @output = program, output
        @recovery = recovery
      end

      # Local input failures exit 2; CONTEXT carries program/output when known.
      def self.invalid_input(message, **context) = new(code: "invalid_input", status: 2, message: message, **context)

      def self.configuration(message) = new(code: "configuration_error", message: message)
    end
  end
end
