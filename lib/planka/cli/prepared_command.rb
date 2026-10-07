require "planka/cli/configuration"

module Planka
  module CLI
    # Resolves a parsed request before authentication and holds executable inputs.
    class PreparedCommand
      def self.build(invocation, env:)
        command = invocation.command
        return new(command.operation, [], {}) unless command.session?

        configuration = Configuration.from_env(env)
        instance = configuration.instance
        arguments = if command.reference?
                      [invocation.reference && instance.resolve(invocation.reference, resource: command.resource,
                                                                                      collection: command.collection, names: command.names?)]
                    else
                      []
                    end
        options = command.preparation(env, instance: instance, flags: invocation.flags)
        new(command.operation, arguments, options, configuration: configuration)
      rescue Instance::InvalidReference => error
        raise Failure.new(code: "invalid_input", status: 2, message: error.message)
      end

      def initialize(operation, arguments, options, configuration: nil)
        @operation, @arguments, @configuration = operation, arguments.freeze, configuration
        @options = options.transform_values { |value| value.is_a?(Array) ? value.freeze : value }.freeze
        freeze
      end

      def requires_session? = !@configuration.nil?
      def connection_options = @configuration.connection_options

      def execute(client = nil)
        arguments = requires_session? ? [client, *@arguments] : @arguments
        @operation.call(*arguments, **@options)
      end
    end
  end
end
