require "uri"
require "planka/cli/failure"

module Planka
  module CLI
    # Owns instance identity and same-instance resource reference resolution.
    class Instance
      InvalidReference = Class.new(StandardError)
      attr_reader :base_url

      def initialize(base_url)
        @base_url = base_url.dup.freeze
        @base = URI(@base_url)
        unless %w[http https].include?(@base.scheme) && @base.host && !@base.userinfo && !@base.query && !@base.fragment
          raise Failure.new(code: "configuration_error", message: "PLANKA_BASE_URL must be an HTTP(S) instance URL without credentials, query, or fragment")
        end
        freeze
      rescue URI::InvalidURIError
        raise Failure.new(code: "configuration_error", message: "Invalid PLANKA_BASE_URL")
      end

      def resolve(value, resource:, collection:)
        return value.dup.freeze if value.match?(/\A\d+\z/)

        reference = URI(value)
        prefix = Regexp.escape(@base.path.sub(%r{/+\z}, ""))
        target = reference.path.match(%r{\A#{prefix}/#{collection}/(\d+)/?\z})
        unless [reference.scheme, reference.host, reference.port] == [@base.scheme, @base.host, @base.port] &&
            target && !reference.userinfo && !reference.query && !reference.fragment
          raise InvalidReference, "#{resource.capitalize} URL must belong to PLANKA_BASE_URL"
        end
        target[1].freeze
      rescue URI::InvalidURIError
        raise InvalidReference, "Invalid #{resource} URL; use a numeric #{resource} ID or same-instance #{resource} URL"
      end
    end
  end
end
