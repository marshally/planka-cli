require_relative "planka_test_helper"

class Planka::SnapshotTest < Minitest::Test
  def included
    {
      "lists" => [ { "id" => "L1", "name" => "ready-for-agent", "type" => "active" } ],
      "cards" => [
        { "id" => "c2", "listId" => "L1", "position" => 131_072, "description" => "second" },
        { "id" => "c1", "listId" => "L1", "position" => 65_536, "description" => "first" },
        { "id" => "c3", "listId" => "L2", "position" => 196_608, "description" => "other list" },
      ],
      "labels" => [ { "id" => "lab", "name" => "enhancement" } ],
      "cardLabels" => [ { "cardId" => "c1", "labelId" => "lab" } ],
      "taskLists" => [ { "id" => "tl", "cardId" => "c1", "name" => "Acceptance criteria" } ],
      "tasks" => [ { "id" => "t", "taskListId" => "tl", "linkedCardId" => nil, "isCompleted" => false } ],
      "cardMemberships" => [ { "cardId" => "c1", "userId" => "u" } ],
    }
  end

  def snapshot = Planka::Snapshot.new(included, base_url: "https://planka.test///")

  def test_to_h_passes_records_through_and_keeps_every_type
    doc = snapshot.to_h

    assert_equal Planka::Snapshot::RECORD_TYPES.sort, doc.keys.sort
    assert_equal "enhancement", doc["labels"].first["name"]
    assert_equal false, doc["tasks"].first["isCompleted"]
    assert_equal [ "cardId", "userId" ], doc["cardMemberships"].first.keys
  end

  def test_cards_are_ordered_by_position_and_gain_a_url
    cards = snapshot.to_h["cards"]

    assert_equal %w[c1 c2 c3], cards.map { |c| c["id"] }
    assert_equal "https://planka.test/cards/c1", cards.first["url"]
    assert_equal "first", cards.first["description"], "descriptions are retained"
  end

  def test_cards_in_filters_to_one_list_in_order
    assert_equal %w[c1 c2], snapshot.cards_in("L1").map { |c| c["id"] }
  end
end
