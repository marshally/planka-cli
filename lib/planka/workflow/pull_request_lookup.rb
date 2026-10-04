require "json"
require "open3"

module Planka
  module Workflow
    # Canonical lookup preserves unknown PRs while keeping tool diagnostics private.
    module PullRequestLookup
      def self.find(url)
        out, _err, status = Open3.capture3("gh", "pr", "view", url, "--json", "state,headRefName")
        return unless status.success?

        json = JSON.parse(out)
        unless json.is_a?(Hash) && %w[OPEN CLOSED MERGED].include?(json["state"]) &&
            json["headRefName"].is_a?(String) && !json["headRefName"].empty?
          raise InvalidResponse, "Invalid GitHub pull request records"
        end
        PullRequest.new(state: json.fetch("state"), head: json.fetch("headRefName"))
      rescue JSON::ParserError, KeyError
        raise InvalidResponse, "Invalid GitHub pull request response"
      rescue Errno::ENOENT
        raise DependencyUnavailable, "Required executable gh is unavailable; install the GitHub CLI for blocker PR inspection"
      end
    end
  end
end
