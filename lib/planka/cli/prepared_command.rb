require "planka/cli/configuration"

module Planka
  module CLI
    # Resolves a parsed request before authentication and holds executable inputs.
    class PreparedCommand
      def self.build(invocation, env:)
        command = invocation.command
        return new(command.reader, [], {}) unless command.session?

        configuration = Configuration.from_env(env)
        instance = configuration.instance
        arguments = if command.reference?
                      [invocation.reference && instance.resolve(invocation.reference, resource: command.resource,
                                                                                      collection: command.collection, names: command.names?)]
                    else
                      []
                    end
        options = { base_url: instance.base_url }
        options.merge!(command.preparation(env, instance: instance, flags: invocation.flags))
        new(command.reader, arguments, options, configuration: configuration)
      rescue Instance::InvalidReference => error
        raise Failure.new(code: "invalid_input", status: 2, message: error.message)
      end

      def initialize(reader, arguments, options, configuration: nil)
        @reader, @arguments, @configuration = reader, arguments.freeze, configuration
        @options = options.transform_values { |value| value.is_a?(Array) ? value.freeze : value }.freeze
        freeze
      end

      def requires_session? = !@configuration.nil?
      def connection_options = @configuration.connection_options

      def execute(client = nil)
        arguments = requires_session? ? [client, *@arguments] : @arguments
        @reader.read(*arguments, **@options)
      end
    end
  end
end
