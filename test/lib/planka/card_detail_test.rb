require_relative "planka_test_helper"

class Planka::CardDetailTest < Minitest::Test
  # Stands in for Client: serves one card (with the task lists, tasks, labels and
  # members GET /api/cards/:id includes), the board that names its labels and
  # lists, and the card's comments.
  class FakeClient
    def card(_id)
      {
        "item" => { "id" => "c1", "name" => "Card", "description" => "Body", "type" => "project", "boardId" => "B", "listId" => "L1", "position" => 65_536 },
        "included" => {
          "cardLabels" => [{ "cardId" => "c1", "labelId" => "lab" }],
          "cardMemberships" => [{ "cardId" => "c1", "userId" => "u1" }],
          "taskLists" => [
            { "id" => "tl2", "cardId" => "c1", "name" => "Blocked by", "position" => 131_072 },
            { "id" => "tl1", "cardId" => "c1", "name" => "Acceptance criteria", "position" => 65_536 },
          ],
          "tasks" => [
            { "id" => "k1", "taskListId" => "tl1", "name" => "a criterion", "isCompleted" => false, "linkedCardId" => nil, "position" => 65_536 },
            { "id" => "b1", "taskListId" => "tl2", "name" => nil, "isCompleted" => true, "linkedCardId" => "blk", "position" => 65_536 },
          ],
        },
      }
    end

    def board(_id)
      {
        "lists" => [{ "id" => "L1", "name" => "ready-for-agent", "type" => "active" }],
        "labels" => [{ "id" => "lab", "name" => "enhancement" }],
        "cards" => [], "cardLabels" => [], "taskLists" => [], "tasks" => [], "cardMemberships" => []
      }
    end

    def comments(_id) = [{ "id" => "cm", "text" => "hello", "userId" => "u2", "createdAt" => "2026-01-01T00:00:00.000Z" }]
  end

  def detail = Planka::Cards::Detail.new(FakeClient.new, base_url: "https://planka.test///").for("c1")

  def test_reports_identity_description_and_url
    doc = detail

    assert_equal "Body", doc["description"]
    assert_equal "ready-for-agent", doc["listName"]
    assert_equal "https://planka.test/cards/c1", doc["url"]
  end

  def test_resolves_label_names_and_members
    doc = detail

    assert_equal [{ "id" => "lab", "name" => "enhancement" }], doc["labels"]
    assert_equal ["u1"], doc["members"]
  end

  def test_orders_task_lists_by_position_with_their_tasks
    lists = detail["taskLists"]

    assert_equal(["Acceptance criteria", "Blocked by"], lists.map { |l| l["name"] })
    assert_equal(["a criterion"], lists.first["tasks"].map { |t| t["name"] })
  end

  def test_reports_linked_blockers_and_comments
    doc = detail

    assert_equal [{ "cardId" => "blk", "taskId" => "b1", "completed" => true }], doc["blockers"]
    assert_equal(["hello"], doc["comments"].map { |c| c["text"] })
  end

  def test_strict_read_rejects_malformed_card_response
    client = FakeClient.new
    def client.card(_id) = { "item" => {}, "included" => {} }

    error = assert_raises(Planka::InvalidResponse) do
      Planka::Cards::Detail.read(client, "c1", base_url: "https://planka.test")
    end

    assert_equal "Invalid card response", error.message
  end

  def test_legacy_detail_preserves_malformed_card_error
    client = FakeClient.new
    def client.card(_id) = { "included" => {} }

    error = assert_raises(KeyError) do
      Planka::Cards::Detail.new(client, base_url: "https://planka.test").for("c1")
    end

    assert_equal "key not found: \"item\"", error.message
  end

  def test_strict_read_translates_related_board_key_error
    client = FakeClient.new
    def client.board(_id) = {}

    error = assert_raises(Planka::InvalidResponse) do
      Planka::Cards::Detail.read(client, "c1", base_url: "https://planka.test")
    end

    assert_equal "Invalid related board records", error.message
  end

  def test_legacy_detail_preserves_related_board_key_error
    client = FakeClient.new
    def client.board(_id) = {}

    assert_raises(KeyError) do
      Planka::Cards::Detail.new(client, base_url: "https://planka.test").for("c1")
    end
  end

  def test_strict_read_rejects_malformed_comments
    client = FakeClient.new
    def client.comments(_id) = nil

    error = assert_raises(Planka::InvalidResponse) do
      Planka::Cards::Detail.read(client, "c1", base_url: "https://planka.test")
    end

    assert_equal "Invalid comment records", error.message
  end

  def test_legacy_detail_preserves_malformed_comment_error
    client = FakeClient.new
    def client.comments(_id) = nil

    assert_raises(NoMethodError) do
      Planka::Cards::Detail.new(client, base_url: "https://planka.test").for("c1")
    end
  end
end
