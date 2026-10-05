module Planka
  # A board as GET /api/boards/:id returns it. Planka sends each record type
  # as a flat list under "included", joined by id; this joins them once and
  # gives each Card its own related records.
  class Board
    # Validated card-to-board lookup shared by card-based readers.
    def self.included_for_card(client, id)
      response = client.card(id)
      board_id = response.is_a?(Hash) && response["item"].is_a?(Hash) && response["item"]["boardId"]
      unless Records.id?(board_id)
        raise InvalidResponse, "Invalid card board reference"
      end
      included = client.board(board_id)
      Boards::Snapshot.validate!(included)
      included
    end

    def initialize(included, base_url: ENV.fetch("PLANKA_BASE_URL"))
      @base_url = base_url.sub(%r{/+\z}, "")
      @included = included
      @lists = included.fetch("lists").to_h { |list| [ list["id"], list ] }
      @labels = included.fetch("labels").to_h { |label| [ label["id"], label["name"] ] }
      @cards = build_cards(included)
    end

    def card(id) = @cards.fetch(id)

    def cards = @cards.values

    def cards_labelled(name)
      raise Error, "no label #{name}" unless @labels.value?(name)

      @included.fetch("cardLabels").filter_map { |cl| @cards[cl["cardId"]] if @labels[cl["labelId"]] == name }
    end

    def list_name(list_id) = @lists[list_id]&.dig("name")

    def label_name(label_id) = @labels[label_id]

    # Resolves a list name to its id, refusing to guess when a board has two
    # lists with the same name.
    def list_id(name) = resolve(@lists.transform_values { |list| list["name"] }, name, "list")

    private

    def resolve(index, name, kind)
      ids = index.select { |_, value| value == name }.keys
      raise Error, "no #{kind} #{name}" if ids.empty?
      raise Error, "ambiguous #{kind} name #{name}: #{ids.join(", ")}" if ids.size > 1

      ids.first
    end

    # Hands each card its own related records, so a Card answers questions
    # about itself without calling back into the board.
    def build_cards(included)
      labels = included.fetch("cardLabels").group_by { |cl| cl["cardId"] }
      task_lists = included.fetch("taskLists").group_by { |task_list| task_list["cardId"] }
      tasks = included.fetch("tasks").group_by { |task| task["taskListId"] }
      memberships = included.fetch("cardMemberships").group_by { |membership| membership["cardId"] }
      included.fetch("cards").to_h do |attrs|
        id = attrs["id"]
        card = Card.new(attrs, url: "#{@base_url}/cards/#{id}", list: @lists[attrs["listId"]],
          label_names: labels.fetch(id, []).filter_map { |cl| @labels[cl["labelId"]] },
          task_lists: task_lists.fetch(id, []).map { |task_list| Card::TaskList.new(name: task_list["name"], tasks: tasks.fetch(task_list["id"], [])) },
          memberships: memberships.fetch(id, []))
        [ id, card ]
      end
    end
  end
end
