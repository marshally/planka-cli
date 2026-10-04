module Planka
  class Card
    attr_reader :id, :name, :position, :created_at, :list_id

    def initialize(board, attrs)
      @board = board
      @id = attrs.fetch("id")
      @name = attrs.fetch("name")
      @list_id = attrs.fetch("listId")
      @position = attrs.fetch("position")
      @created_at = attrs.fetch("createdAt")
    end

    def list_name = @board.list_name(list_id)
    def list_type = @board.list_type(list_id)
    def label_names = @board.label_names(id)
    def task_list_names = @board.task_list_names(id)
    def tasks = @board.tasks(id)
    def tasks_in(list_name) = @board.tasks_in(id, list_name)
    def members = @board.members(id)
    def memberships = @board.memberships(id)
    def open? = list_type == "active"
    def closed? = list_type == "closed"
    def labelled?(name) = label_names.include?(name)

    def url = "#{@board.base_url}/cards/#{id}"
    def to_s = "#{name} (#{url})"

  end
end
