module Planka
  # A board as GET /api/boards/:id returns it. Planka sends each record type
  # as a flat list under "included", joined by id; this indexes them once so
  # a Card can answer questions about itself.
  class Board
    attr_reader :base_url

    def initialize(included, base_url: ENV.fetch("PLANKA_BASE_URL"))
      @base_url = base_url.sub(%r{/+\z}, "")
      @included = included
      @cards = included.fetch("cards").to_h { |attrs| [ attrs["id"], Card.new(self, attrs) ] }
      @lists = included.fetch("lists").to_h { |list| [ list["id"], list["name"] ] }
      @labels = included.fetch("labels").to_h { |label| [ label["id"], label["name"] ] }
      @task_lists = included.fetch("taskLists").group_by { |task_list| task_list["cardId"] }
      @tasks = included.fetch("tasks").group_by { |task| task["taskListId"] }
      @list_types = included.fetch("lists").to_h { |list| [ list["id"], list["type"] ] }
      @memberships = included.fetch("cardMemberships").group_by { |membership| membership["cardId"] }
    end

    def card(id) = @cards.fetch(id)

    def cards = @cards.values

    def cards_labelled(name)
      raise Error, "no label #{name}" unless @labels.value?(name)

      @included.fetch("cardLabels").filter_map { |cl| @cards[cl["cardId"]] if @labels[cl["labelId"]] == name }
    end

    def list_name(list_id) = @lists[list_id]

    def label_names(card_id)
      @included.fetch("cardLabels").filter_map { |cl| @labels[cl["labelId"]] if cl["cardId"] == card_id }
    end

    def task_list_names(card_id) = task_lists(card_id).map { |task_list| task_list["name"] }

    def tasks(card_id) = task_lists(card_id).flat_map { |task_list| @tasks.fetch(task_list["id"], []) }

    def members(card_id) = memberships(card_id).map { |membership| membership["userId"] }

    def memberships(card_id) = @memberships.fetch(card_id, [])

    def tasks_in(card_id, list_name)
      task_lists(card_id).select { |task_list| task_list["name"] == list_name }.flat_map { |task_list| @tasks.fetch(task_list["id"], []) }
    end

    def list_type(list_id) = @list_types[list_id]

    def label_name(label_id) = @labels[label_id]

    # Resolves a list name to its id, refusing to guess when a board has two
    # lists with the same name.
    def list_id(name) = resolve(@lists, name, "list")

    # Resolves a label name to its id, refusing to guess on duplicates.
    def label_id(name) = resolve(@labels, name, "label")

    private

    def resolve(index, name, kind)
      ids = index.select { |_, value| value == name }.keys
      raise Error, "no #{kind} #{name}" if ids.empty?
      raise Error, "ambiguous #{kind} name #{name}: #{ids.join(", ")}" if ids.size > 1

      ids.first
    end

    def task_lists(card_id) = @task_lists.fetch(card_id, [])
  end
end
