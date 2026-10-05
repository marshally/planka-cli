require "planka/cli/instance"
require "planka/cli/failure"

module Planka
  module CLI
    # Captures validated connection settings; credentials never enter presentation.
    class Configuration
      REQUIRED = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].freeze
      attr_reader :instance

      def self.from_env(env)
        values = REQUIRED.map { |key| env[key] }
        missing = REQUIRED.zip(values).filter_map { |key, value| key if value.to_s.strip.empty? }
        unless missing.empty?
          raise Failure.new(code: "configuration_error", message: "Missing required environment: #{missing.join(', ')}")
        end
        new(*values)
      end

      def initialize(base_url, email, password)
        @instance = Instance.new(base_url)
        @email, @password = [email, password].map { |value| value.dup.freeze }
        freeze
      end

      def connection_options = { base_url: @instance.base_url, email: @email, password: @password }
      def inspect = "#<#{self.class} connection settings redacted>"
    end
  end
end
