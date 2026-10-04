require "forwardable"

module Planka
  module Workflow
    # Interprets general card data according to the agent workflow conventions.
    class Card
      extend Forwardable
      READY_LIST = "ready-for-agent"
      IN_PROGRESS_LIST = "in-progress"
      CRITERIA_LIST = "Acceptance criteria"

      def_delegators :@card, :id, :name, :position, :created_at, :url, :to_s, :open?, :closed?, :labelled?

      def initialize(board, card)
        @board, @card = board, card
      end

      def ready? = @card.list_name == READY_LIST
      def in_progress? = @card.list_name == IN_PROGRESS_LIST
      def ticket? = @card.task_list_names.include?(CRITERIA_LIST)
      def features = @card.label_names.select { |name| name.start_with?("feature:") }
      def unticked_criteria = @card.tasks_in(CRITERIA_LIST).reject { |task| task["isCompleted"] }.map { |task| task["name"] }
      def claimed? = @card.members.any?
      def claimed_by?(user_id) = @card.members.include?(user_id)
      def takeable? = ready? && !claimed? && open_blockers.empty?

      def claimed_at(user_id)
        membership = @card.memberships.find { |record| record["userId"] == user_id }
        membership && Time.iso8601(membership.fetch("createdAt"))
      end

      def blockers = blocking_tasks.map { |task| @board.card(task["linkedCardId"]) }
      def open_blockers = blocking_tasks.reject { |task| task["isCompleted"] }.map { |task| @board.card(task["linkedCardId"]) }

      private

      # Linked tasks represent blockers in this workflow.
      def blocking_tasks = @card.tasks.select { |task| task["linkedCardId"] }
    end
  end
end
