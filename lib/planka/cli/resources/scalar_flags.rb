module Planka
  module CLI
    module Resources
      # Local checks for commands whose flags each take one value: no conflicting
      # repeats, no blank values, and a positive integer --limit. Shared by resource
      # commands and workflow resume ticket.
      module ScalarFlags
        def self.error(flags)
          return "Conflicting scalar flags" if flags.values.any? { |values| values.uniq.size > 1 }
          return "Flags must have nonempty values" if flags.values.any? { |values| values.first.to_s.strip.empty? }
          return "--limit must be a positive integer" if flags[:limit] && !flags[:limit].first.match?(/\A[1-9]\d*\z/)
        end
      end
    end
  end
end
