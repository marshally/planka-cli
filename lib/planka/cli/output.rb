require "json"
require "planka/cli/failure"
require "planka/client"

module Planka
  module CLI
    # Owns canonical presentation and status; it never terminates the process.
    class Output
      def initialize(stdout:, stderr:)
        @stdout, @stderr = stdout, stderr
      end

      def help(invocation)
        @stdout.puts invocation.help_text
        0
      end

      def success(invocation, data)
        command = invocation.command
        meta = {}
        if data.is_a?(CollectionResult)
          meta["complete"] = data.complete
          data = data.data
        end
        if command.mutation?
          meta["changed"] = data.changed
          data = data.data
        end
        if invocation.output == "json"
          @stdout.puts JSON.generate({ "data" => command.project(data), "meta" => meta, "error" => nil })
        else
          @stdout.puts command.format(data)
          @stdout.puts "Results truncated; use a larger --limit or omit it." if meta["complete"] == false
        end
        0
      end

      def failure(error, invocation: nil)
        failure = expected_failure(error)
        program = invocation&.program || failure.program || "planka"
        format = invocation&.output || failure.output || "human"
        @stderr.puts "#{program}: #{failure.message}"
        if format == "json"
          meta = invocation&.command&.mutation? ? { "changed" => false }.merge(failure.meta) : failure.meta
          if invocation&.command&.collection_read? && invocation.reference.nil?
            meta = { "complete" => false }.merge(meta)
          end
          details = { "code" => failure.code, "message" => failure.message }
          details["recovery"] = failure.recovery if failure.recovery
          @stdout.puts JSON.generate({ "data" => failure.data, "meta" => meta, "error" => details })
        end
        failure.status
      end

      def cleanup_failure(invocation)
        result = invocation.command.mutation? ? "operation result" : "read result"
        @stderr.puts "#{invocation.program}: session cleanup failed; the #{result} is unchanged"
      end

      private

      def expected_failure(error)
        case error
        when Failure then error
        when ReferenceError
          Failure.new(code: error.code, status: error.status, message: error.message)
        when CollectionFailure
          primary = expected_failure(error.cause)
          Failure.new(code: primary.code, message: primary.message,
                      data: error.data, meta: { "complete" => false })
        when MutationFailure
          primary = expected_failure(error.cause)
          code = error.uncertain ? "unknown_outcome" : (error.changed ? "partial_failure" : primary.code)
          message = error.uncertain ? "Mutation outcome is unknown" : primary.message
          message += "; earlier changes are preserved" if error.changed
          Failure.new(code: code, message: "#{message}; read back the affected resources before retrying",
                      data: error.data, meta: { "changed" => error.changed }, recovery: error.recovery)
        when Planka::DependencyUnavailable
          Failure.configuration(error.message)
        when Planka::Client::HTTPError
          code = { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found" }.fetch(error.status, "api_error")
          Failure.new(code: code, message: "API request failed (HTTP #{error.status}); verify the resource and access permissions")
        when Planka::Error
          Failure.new(code: "api_error", message: "Could not read complete resource details; verify server availability and API compatibility")
        when *Planka::Client::NETWORK_ERRORS
          Failure.new(code: "network_error", message: "Could not reach Planka; check the instance URL and network")
        else
          # Programming mistakes must not masquerade as malformed server data.
          raise error
        end
      end
    end
  end
end
