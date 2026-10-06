require "time"

module Planka
  # Shared checks for Planka response records. Each reader still decides which
  # records it validates and which failure it reports.
  module Records
    def self.id?(value) = value.is_a?(String) && value.match?(/\A\d+\z/)

    def self.timestamp?(value)
      return false unless value.is_a?(String)

      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end

    def self.user!(user)
      raise InvalidResponse, "Invalid signed-in user" unless user.is_a?(Hash) && user["id"].is_a?(String) && !user["id"].empty?

      user
    end
  end
end
