require "planka"

module Planka
  module Workflow
    ConfigurationError = Class.new(Planka::Error)

    # Captures convention settings independently of shared connection credentials.
    class Configuration
      def self.from_env(env) = new(branch_prefix: env["PLANKA_BRANCH_PREFIX"] || "")

      def initialize(branch_prefix:)
        @branch_prefix = branch_prefix.dup.freeze
      end

      def branch_prefix
        BranchName.max_length(@branch_prefix)
        @branch_prefix
      rescue Planka::Error
        raise ConfigurationError, "PLANKA_BRANCH_PREFIX leaves too little space; use at most 55 characters"
      end
    end
  end
end
