require "json"
require "open3"

module Planka
  module Workflow
    # Looks blocker pull requests up with the gh CLI. Each lookup answers
    # #find(url) with a PullRequest, or nil when gh cannot find it.
    module PullRequestLookup
      def self.command(url) = ["gh", "pr", "view", url, "--json", "state,headRefName"]

      # Canonical lookup preserves unknown PRs while keeping tool diagnostics private.
      def self.find(url)
        out, _err, status = Open3.capture3(*command(url))
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

      # Legacy next-card lookup: gh's diagnostics pass through to stderr and
      # its failures are not translated, as the legacy contract retains.
      module Legacy
        def self.find(url)
          out, status = Open3.capture2(*PullRequestLookup.command(url))
          return unless status.success?

          json = JSON.parse(out)
          PullRequest.new(state: json.fetch("state"), head: json.fetch("headRefName"))
        end
      end
    end
  end
end
