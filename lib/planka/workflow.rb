require "planka"

# Agent conventions are explicitly loaded, independently of CLI adapters.
module Planka
  module Workflow
  end
end

require_relative "workflow/card"
require_relative "workflow/board"
require_relative "workflow/handoff"
require_relative "workflow/handoff_comments"
require_relative "workflow/pull_request"
require_relative "workflow/pull_request_lookup"
require_relative "workflow/blocker"
require_relative "workflow/next_card"
require_relative "workflow/queue_snapshot"
require_relative "workflow/next_selection"
require_relative "workflow/branch_name"
require_relative "workflow/loop_lock"
require_relative "workflow/spec_sweep"
require_relative "workflow/blocking"
require_relative "workflow/pending_criteria"
require_relative "workflow/publishing"
require_relative "workflow/prime"
require_relative "workflow/guide"
require_relative "workflow/configuration"
require_relative "workflow/mutation_progress"
require_relative "workflow/claim"
require_relative "workflow/claim/scope"
require_relative "workflow/claim/progress"
require_relative "workflow/claim/card"
require_relative "workflow/claim_status"
require_relative "workflow/criteria/scope"
require_relative "workflow/criteria/fill"
require_relative "workflow/resume/progress"
require_relative "workflow/resume/ticket"
require_relative "workflow/create/spec"
require_relative "workflow/create/ticket"
