module Planka
  module CLI
    # Immutable parsed command, output choice, local arguments, and flags.
    class Invocation
      attr_reader :program, :output, :command, :reference, :flags, :help_text

      def initialize(program:, output:, command:, reference:, flags:, help_text:)
        @program, @output = program.dup.freeze, output.dup.freeze
        @command, @flags = snapshot(command), snapshot(flags)
        @reference, @help_text = snapshot(reference), snapshot(help_text)
        freeze
      end

      def help? = !@help_text.nil?

      private

      def snapshot(value)
        case value
        when Hash then value.transform_values { |entry| snapshot(entry) }.freeze
        when Array then value.map { |entry| snapshot(entry) }.freeze
        when String then value.dup.freeze
        else value
        end
      end
    end
  end
end
