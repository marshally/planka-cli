require "planka/cli/parser"
require "planka/cli/prepared_command"
require "planka/cli/output"

module Planka
  # Coordinates the canonical path while legacy executables keep their adapters.
  module CanonicalCLI
    module_function

    def run(args, legacy_commands:, env: ENV, stdout: $stdout, stderr: $stderr, extensions: [])
      output = CLI::Output.new(stdout: stdout, stderr: stderr)
      invocation = CLI::Parser.parse(args, legacy_commands: legacy_commands, extensions: extensions)
      return output.help(invocation) if invocation.help?
      prepared = CLI::PreparedCommand.build(invocation, env: env)
      return output.success(invocation, prepared.execute) unless prepared.requires_session?

      cleanup = ->(_error) { output.cleanup_failure(invocation) }
      data = Client.session(**prepared.connection_options, validate_responses: true, on_cleanup_error: cleanup) do |client|
        prepared.execute(client)
      end
      output.success(invocation, data)
    rescue StandardError => error
      output.failure(error, invocation: invocation)
    end
  end
end
