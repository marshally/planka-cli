require "minitest/autorun"
require "planka"
require_relative "fake_planka"

class CardMembersResourceTest < Minitest::Test
  CARD = FakePlanka::PARENT_CARD
  USER = "600000000000000001"
  MEMBERSHIP = "800000000000000001"

  def setup
    @server = FakePlanka.new
    @server.users << { "id" => USER, "name" => "Ada", "username" => "ada", "email" => "private@example.com" }
    @server.board_memberships << { "id" => "900000000000000001", "boardId" => @server.board_id, "userId" => USER, "role" => "editor" }
  end

  def teardown = @server.stop

  def with_members
    Planka::Client.session(base_url: @server.base_url, email: "bot@example.com", password: "fixture", validate_responses: true) do |client|
      yield Planka::Cards::Members.new(client, card_id: CARD)
    end
  end

  def assignment
    { "id" => MEMBERSHIP, "cardId" => CARD, "userId" => USER, "createdAt" => "2026-10-05T00:00:00Z", "updatedAt" => nil }
  end

  def expected_member
    { "id" => USER, "name" => "Ada", "username" => "ada", "cardId" => CARD,
      "membershipId" => MEMBERSHIP, "createdAt" => "2026-10-05T00:00:00Z", "updatedAt" => nil }
  end

  def test_all_returns_a_complete_collection_of_public_member_identities
    @server.memberships << assignment
    with_members do |members|
      result = members.all
      assert_equal [expected_member], result.data
      assert_equal true, result.complete
    end
  end

  def test_find_returns_one_assignment_by_id_or_exact_name
    @server.memberships << assignment
    with_members do |members|
      assert_equal expected_member, members.find(USER)
      assert_equal expected_member, members.find("Ada")
    end
  end

  def test_add_is_visible_through_the_same_resource_and_repeated_add_is_a_noop
    with_members do |members|
      assert_empty members.all.data
      added = members.add(USER)
      assert_equal true, added.changed
      assert_equal true, added.data.fetch("assigned")
      assert_equal added.data.except("assigned"), members.find(USER)
      assert_equal([USER], members.all.data.map { |member| member.fetch("id") })
      assert_equal false, members.add("Ada").changed
    end
  end

  def test_remove_preserves_assignment_metadata_and_absent_assignment_is_a_noop
    @server.memberships << assignment
    with_members do |members|
      removed = members.remove(USER)
      assert_equal true, removed.changed
      assert_equal expected_member.merge("assigned" => false), removed.data
      assert_empty members.all.data
      assert_equal false, members.remove("Ada").changed
      error = assert_raises(Planka::ReferenceError) { members.find(USER) }
      assert_equal "not_found", error.code
    end
  end
end
