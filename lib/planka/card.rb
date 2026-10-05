module Planka
  # One card with the related records its board sent for it: its list, label
  # names, named task lists with their tasks, and memberships.
  class Card
    TaskList = Data.define(:name, :tasks)

    attr_reader :id, :name, :position, :created_at, :list_id, :url, :label_names, :memberships

    def initialize(attrs, url:, list:, label_names:, task_lists:, memberships:)
      @id = attrs.fetch("id")
      @name = attrs.fetch("name")
      @list_id = attrs.fetch("listId")
      @position = attrs.fetch("position")
      @created_at = attrs.fetch("createdAt")
      @url, @list, @label_names, @memberships = url, list, label_names, memberships
      @task_lists = task_lists
    end

    def list_name = @list&.dig("name")
    def list_type = @list&.dig("type")
    def task_list_names = @task_lists.map(&:name)
    def tasks = @task_lists.flat_map(&:tasks)
    def tasks_in(list_name) = @task_lists.select { |task_list| task_list.name == list_name }.flat_map(&:tasks)
    def members = memberships.map { |membership| membership["userId"] }
    def open? = list_type == "active"
    def closed? = list_type == "closed"
    def labelled?(name) = label_names.include?(name)

    def to_s = "#{name} (#{url})"
  end
end
