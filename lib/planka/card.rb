module Planka
  class Card
    READY_LIST = "ready-for-agent"
    IN_PROGRESS_LIST = "in-progress"
    CRITERIA_LIST = "Acceptance criteria"

    attr_reader :id, :name, :position, :created_at

    def initialize(board, attrs)
      @board = board
      @id = attrs.fetch("id")
      @name = attrs.fetch("name")
      @list_id = attrs.fetch("listId")
      @position = attrs.fetch("position")
      @created_at = attrs.fetch("createdAt")
    end

    def ready? = @board.list_name(@list_id) == READY_LIST
    def claimed? = @board.members(id).any?
    def claimed_by?(user_id) = @board.members(id).include?(user_id)

    def claimed_at(user_id)
      membership = @board.memberships(id).find { |m| m["userId"] == user_id }
      membership && Time.iso8601(membership.fetch("createdAt"))
    end

    def unticked_criteria = @board.tasks_in(id, CRITERIA_LIST).reject { |task| task["isCompleted"] }.map { |task| task["name"] }
    def open? = @board.list_type(@list_id) == "active"
    def closed? = @board.list_type(@list_id) == "closed"
    def in_progress? = @board.list_name(@list_id) == IN_PROGRESS_LIST
    def ticket? = @board.task_list_names(id).include?(CRITERIA_LIST)
    def labelled?(name) = @board.label_names(id).include?(name)
    def features = @board.label_names(id).select { |name| name.start_with?("feature:") }
    def takeable? = ready? && !claimed? && open_blockers.empty?

    # Blocking is a task linked to the blocker card; Planka completes it when
    # the blocker closes. Linked tasks are used for nothing else.
    def blockers = blocking_tasks.map { |task| @board.card(task["linkedCardId"]) }
    def open_blockers = blocking_tasks.reject { |task| task["isCompleted"] }.map { |task| @board.card(task["linkedCardId"]) }

    def url = "#{@board.base_url}/cards/#{id}"
    def to_s = "#{name} (#{url})"

    private

    def blocking_tasks = @board.tasks(id).select { |task| task["linkedCardId"] }
  end
end
