require_relative "planka_test_helper"

class Planka::LabelsTest < Minitest::Test
  # Stands in for Client: serves a board's labels and a card's current labels,
  # and records creates and applications.
  class FakeClient
    attr_reader :writes

    def initialize(labels: [], card_labels: [], board_id: "B")
      @labels = labels
      @card_labels = card_labels
      @board_id = board_id
      @writes = []
    end

    def board(_id) = { "labels" => @labels, "cardLabels" => @card_labels }

    def card(_id) = { "item" => { "boardId" => @board_id }, "included" => { "cardLabels" => @card_labels } }

    def create_label(board_id, **attrs)
      @writes << [:create_label, board_id, attrs]
      { "id" => "label-new", "name" => attrs[:name], "color" => attrs[:color], "position" => attrs[:position] }
    end

    def add_card_label(card_id, label_id)
      @writes << [:add_card_label, card_id, label_id]
      { "id" => "cl-new", "cardId" => card_id, "labelId" => label_id }
    end
  end

  def labels(client) = Planka::Labels.new(client)

  def test_find_or_create_appends_a_new_label
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "bug", "position" => 65_536 }])

    result = labels(client).find_or_create(board_id: "B", name: "feature:x", color: "berry-red")

    assert result["created"]
    assert_equal [[:create_label, "B", { name: "feature:x", color: "berry-red", position: 131_072 }]], client.writes
  end

  def test_find_or_create_reuses_a_label_with_the_same_name
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "enhancement", "position" => 1 }])

    result = labels(client).find_or_create(board_id: "B", name: "enhancement", color: "berry-red")

    refute result["created"]
    assert_equal "l1", result["label"]["id"]
    assert_empty client.writes
  end

  def test_find_or_create_rejects_a_duplicated_name
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "enhancement" }, { "id" => "l2", "name" => "enhancement" }])

    assert_raises(Planka::Error) { labels(client).find_or_create(board_id: "B", name: "enhancement", color: "berry-red") }
  end

  def test_apply_resolves_a_name_and_adds_it_once
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "enhancement" }])

    result = labels(client).apply(card_id: "C", label: "enhancement")

    assert result["created"]
    assert_equal [[:add_card_label, "C", "l1"]], client.writes
    assert_equal "l1", result["labelId"]
  end

  def test_apply_accepts_a_label_id_directly
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "enhancement" }])

    result = labels(client).apply(card_id: "C", label: "l1")

    assert result["created"]
    assert_equal [[:add_card_label, "C", "l1"]], client.writes
  end

  def test_apply_is_idempotent_when_the_label_is_already_on_the_card
    client = FakeClient.new(
      labels: [{ "id" => "l1", "name" => "enhancement" }],
      card_labels: [{ "cardId" => "C", "labelId" => "l1" }]
    )

    result = labels(client).apply(card_id: "C", label: "enhancement")

    refute result["created"]
    assert_empty client.writes, "an existing association is not added again"
  end

  def test_apply_rejects_a_duplicated_name
    client = FakeClient.new(labels: [{ "id" => "l1", "name" => "enhancement" }, { "id" => "l2", "name" => "enhancement" }])

    error = assert_raises(Planka::Error) { labels(client).apply(card_id: "C", label: "enhancement") }

    assert_includes error.message, "ambiguous label name"
  end

  def test_apply_rejects_an_unknown_name
    error = assert_raises(Planka::Error) { labels(FakeClient.new).apply(card_id: "C", label: "nope") }

    assert_equal "no label nope", error.message
  end
end
