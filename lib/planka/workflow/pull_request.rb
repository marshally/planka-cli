module Planka
  module Workflow
    # A blocker's pull request as GitHub reports it.
    PullRequest = Data.define(:state, :head) do
      def merged? = state == "MERGED"
    end
  end
end
