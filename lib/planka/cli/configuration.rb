require "uri"
require "planka/cli/failure"

module Planka
  module CLI
    # Validated settings for one invocation, with instance-bound reference resolution.
    class Configuration
      REQUIRED = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].freeze
      attr_reader :base_url

      def self.from_env(env)
        values = REQUIRED.map { |key| env[key] }
        missing = REQUIRED.zip(values).filter_map { |key, value| key if value.to_s.strip.empty? }
        unless missing.empty?
          raise Failure.new(code: "configuration_error", message: "Missing required environment: #{missing.join(', ')}")
        end
        new(*values)
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
        return nil unless invocation.reference
        resolve_resource(invocation.reference, resource: invocation.resource, collection: invocation.collection)
      end

      def resolve_resource(value, resource:, collection:)
        return value if value.match?(/\A\d+\z/)

        reference = URI(value)
        prefix = Regexp.escape(@base.path.sub(%r{/+\z}, ""))
        target = reference.path.match(%r{\A#{prefix}/#{collection}/(\d+)/?\z})
        unless [reference.scheme, reference.host, reference.port] == [@base.scheme, @base.host, @base.port] &&
            target && !reference.userinfo && !reference.query && !reference.fragment
          raise Failure.new(code: "invalid_input", status: 2, message: "#{resource.capitalize} URL must belong to PLANKA_BASE_URL")
        end
        target[1]
      rescue URI::InvalidURIError
        raise Failure.new(code: "invalid_input", status: 2, message: "Invalid #{resource} URL; use a numeric #{resource} ID or same-instance #{resource} URL")
      end
    end
  end
end
