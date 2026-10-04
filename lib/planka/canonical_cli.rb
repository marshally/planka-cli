require "planka/cli/invocation"
require "planka/cli/configuration"
require "planka/cli/output"

module Planka
  # Coordinates the canonical path while legacy executables keep their adapters.
  module CanonicalCLI
    module_function

    def run(args, legacy_commands:, env: ENV, stdout: $stdout, stderr: $stderr, extensions: [])
      output = CLI::Output.new(stdout: stdout, stderr: stderr)
      invocation = CLI::Invocation.parse(args, legacy_commands: legacy_commands, extensions: extensions)
      return output.help(invocation) if invocation.help?
      return output.success(invocation, invocation.execute) unless invocation.requires_session?

      configuration = CLI::Configuration.from_env(env)
      target = configuration.resolve_reference(invocation)
      reader_options = invocation.reader_options(configuration, env: env)
      cleanup = ->(_error) { output.cleanup_failure(invocation) }
      data = Client.session(**configuration.connection_options, validate_responses: true, on_cleanup_error: cleanup) do |client|
        invocation.execute(client, target, **reader_options)
      end
      output.success(invocation, data)
    rescue StandardError => error
      output.failure(error, invocation: invocation)
    end
  end
end
