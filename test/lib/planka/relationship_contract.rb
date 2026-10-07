# Public behavior shared by card-member and card-label relationships.
module RelationshipContract
  def test_relationship_changes_are_visible_and_repeated_changes_are_noops
    with_relationship do |relationships, id, name|
      assert_equal false, relationships.include?(id)
      assert_equal true, relationships.add(name).changed
      assert_equal true, relationships.include?(id)
      assert_equal false, relationships.add(id).changed
      assert_equal true, relationships.remove(id).changed
      assert_equal false, relationships.include?(name)
      assert_equal false, relationships.remove(name).changed
    end
  end

  def test_unknown_targets_are_reference_errors_not_absent_relationships
    with_relationship do |relationships|
      error = assert_raises(Planka::ReferenceError) { relationships.include?("no-such-target") }
      assert_equal "not_found", error.code
    end
  end

  def test_ambiguous_targets_are_reference_errors_not_absent_relationships
    duplicate_relationship_name
    with_relationship do |relationships, _id, name|
      error = assert_raises(Planka::ReferenceError) { relationships.include?(name) }
      assert_equal "invalid_input", error.code
    end
  end

  def test_failed_reads_raise_instead_of_reporting_absent_relationships
    @server.inject("GET", %r{/api/cards/}, 403)
    with_relationship do |relationships, id|
      error = assert_raises(Planka::Client::HTTPError) { relationships.include?(id) }
      assert_equal 403, error.status
    end
  end

  def test_malformed_reads_raise_instead_of_reporting_absent_relationships
    @server.inject("GET", %r{/api/cards/}, :malformed_card)
    with_relationship do |relationships, id|
      assert_raises(Planka::InvalidResponse) { relationships.include?(id) }
    end
  end
end
