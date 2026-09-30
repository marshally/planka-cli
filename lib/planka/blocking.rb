module Planka
  # Records that a card is blocked by others, as tasks linked to the blocker
  # cards in a "Blocked by" task list. Planka completes a linked task when its
  # card closes, so the list is fully ticked once the card is unblocked.
  # Linking is idempotent: blockers already linked are skipped.
  class Blocking
    TASK_LIST_NAME = "Blocked by"
    POSITION_GAP = 65_536

    # client answers #card(id), #create_task_list and #create_task.
    def initialize(client)
      @client = client
    end

    # Returns one line per blocker saying what happened.
    def link(blocked, blockers)
      raise Error, "a card cannot block itself" if blockers.include?(blocked)

      included = @client.card(blocked).fetch("included")
      task_list = blocked_by_list(blocked, included.fetch("taskLists"))
      linked = included.fetch("tasks").select { |task| task["taskListId"] == task_list["id"] }

      blockers.uniq.map do |blocker|
        next "already linked: #{blocker}" if linked.any? { |task| task["linkedCardId"] == blocker }

        task = @client.create_task(task_list["id"], linkedCardId: blocker, position: next_position(linked))
        linked << task
        "linked: #{blocker} (#{task["isCompleted"] ? "closed" : "open"})"
      end
    end

    private

    def blocked_by_list(card_id, task_lists)
      task_lists.find { |task_list| task_list["name"] == TASK_LIST_NAME } ||
        @client.create_task_list(card_id, name: TASK_LIST_NAME, position: next_position(task_lists), showOnFrontOfCard: true)
    end

    def next_position(records) = (records.map { |record| record["position"].to_f }.max || 0) + POSITION_GAP
  end
end
