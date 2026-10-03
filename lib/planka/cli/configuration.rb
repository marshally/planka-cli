require "uri"
require "planka/cli/failure"

module Planka
  module CLI
    # Validated settings for one invocation, with instance-bound reference resolution.
    class Configuration
      REQUIRED = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].freeze
      attr_reader :base_url

      def self.from_env(env)
        missing = REQUIRED.select { |key| env[key].to_s.strip.empty? }
        unless missing.empty?
          raise Failure.new(code: "configuration_error", message: "Missing required environment: #{missing.join(', ')}")
        end
        new(*REQUIRED.map { |key| env.fetch(key) })
      end

      def initialize(base_url, email, password)
        @base_url, @email, @password = [base_url, email, password].map { |value| value.dup.freeze }
        @base = URI(@base_url)
        unless %w[http https].include?(@base.scheme) && @base.host && !@base.userinfo && !@base.query && !@base.fragment
          raise Failure.new(code: "configuration_error", message: "PLANKA_BASE_URL must be an HTTP(S) instance URL without credentials, query, or fragment")
        end
      rescue URI::InvalidURIError
        raise Failure.new(code: "configuration_error", message: "Invalid PLANKA_BASE_URL")
      end

      def connection_options = { base_url: @base_url, email: @email, password: @password }
      def inspect = "#<#{self.class} connection settings redacted>"

      def resolve_reference(invocation)
        return invocation.reference if invocation.reference.match?(/\A\d+\z/)

        reference = URI(invocation.reference)
        prefix = Regexp.escape(@base.path.sub(%r{/+\z}, ""))
        target = reference.path.match(%r{\A#{prefix}/#{invocation.collection}/(\d+)/?\z})
        unless [reference.scheme, reference.host, reference.port] == [@base.scheme, @base.host, @base.port] &&
            target && !reference.userinfo && !reference.query && !reference.fragment
          raise Failure.new(code: "invalid_input", status: 2, message: "#{invocation.resource.capitalize} URL must belong to PLANKA_BASE_URL")
        end
        target[1]
      rescue URI::InvalidURIError
        raise Failure.new(code: "invalid_input", status: 2, message: "Invalid #{invocation.resource} URL; use a numeric #{invocation.resource} ID or same-instance #{invocation.resource} URL")
      end
    end
  end
end
