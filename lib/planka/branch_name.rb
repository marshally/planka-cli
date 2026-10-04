require "planka/workflow"

module Planka
  # Legacy environment defaults stay in this compatibility adapter.
  module BranchName
    def self.for(card, prefix: ENV.fetch("PLANKA_BRANCH_PREFIX", "")) = Workflow::BranchName.for(card, prefix: prefix)
    def self.read(...) = Workflow::BranchName.read(...)
    def self.max_length(...) = Workflow::BranchName.max_length(...)
    def self.slug(...) = Workflow::BranchName.slug(...)
    def self.fit(...) = Workflow::BranchName.fit(...)
  end
end
