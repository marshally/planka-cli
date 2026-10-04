require "json"
require "open3"

module Planka
  module Workflow
    PullRequest = Data.define(:state, :head) do
      # Looks a PR up with the gh CLI; nil when gh can't find it.
      def self.find(url)
        out, status = Open3.capture2("gh", "pr", "view", url, "--json", "state,headRefName")
        return unless status.success?

        json = JSON.parse(out)
        new(state: json.fetch("state"), head: json.fetch("headRefName"))
      end

      def merged? = state == "MERGED"
    end
  end
end
