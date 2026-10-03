require "json"
require "planka/cli/failure"
require "planka/client"

module Planka
  module CLI
    # Owns canonical presentation and status; it never terminates the process.
    class Output
      NETWORK_ERRORS = [SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError].freeze

      def initialize(stdout:, stderr:)
        @stdout, @stderr = stdout, stderr
      end

      def help(invocation)
        @stdout.puts invocation.help_text
        0
      end

      def success(invocation, data)
        @stdout.puts(invocation.output == "json" ? JSON.generate({ "data" => data, "meta" => {}, "error" => nil }) :
          Planka::CLI.public_send(invocation.formatter, data))
        0
      end

      def failure(error, invocation: nil)
        failure = expected_failure(error)
        program = invocation&.program || failure.program || "planka"
        format = invocation&.output || failure.output || "human"
        @stderr.puts "#{program}: #{failure.message}"
        if format == "json"
          @stdout.puts JSON.generate({ "data" => failure.data, "meta" => failure.meta,
            "error" => { "code" => failure.code, "message" => failure.message } })
        end
        failure.status
      end

      def cleanup_failure(invocation)
        @stderr.puts "#{invocation.program}: session cleanup failed; the read result is unchanged"
      end

      private

      def expected_failure(error)
        case error
        when Failure then error
        when Planka::Client::HTTPError
          code = { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found" }.fetch(error.status, "api_error")
          Failure.new(code: code, message: "API request failed (HTTP #{error.status}); verify the resource and access permissions")
        when Planka::Error
          Failure.new(code: "api_error", message: "Could not read complete resource details; verify server availability and API compatibility")
        when *NETWORK_ERRORS
          Failure.new(code: "network_error", message: "Could not reach Planka; check the instance URL and network")
        else
          # Programming mistakes must not masquerade as malformed server data.
          raise error
        end
      end
    end
  end
end
