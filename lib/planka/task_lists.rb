module Planka
  # Creates a named task list on a card, or renames an existing one by id while
  # keeping its tasks. Renaming takes an id, never a name, so it can never change
  # the wrong list.
  #
  # client answers #card, #create_task_list and #update_task_list.
  class TaskLists
    POSITION_GAP = 65_536

    def initialize(client)
      @client = client
    end

    def create(card_id:, name:, position: nil)
      position ||= next_position(Array(@client.card(card_id).fetch("included")["taskLists"]))
      list = @client.create_task_list(card_id, name:, position:, showOnFrontOfCard: false)
      { "taskList" => slim(list), "created" => true }
    end

    def rename(task_list_id:, name:)
      list = @client.update_task_list(task_list_id, name:)
      { "taskList" => slim(list), "renamed" => true }
    end

    private

    def slim(list) = list.slice("id", "cardId", "name", "position")

    def next_position(records) = (records.map { |record| record["position"].to_f }.max || 0) + POSITION_GAP
  end
end
