require_relative "planka_test_helper"

class Planka::PositionTest < Minitest::Test
  def test_an_empty_collection_starts_one_gap_in
    assert_equal 65_536, Planka::Position.after([])
  end

  def test_appends_one_gap_after_the_highest_position
    records = [ { "position" => 65_536 }, { "position" => "196608" }, { "position" => 131_072 } ]

    assert_equal 262_144, Planka::Position.after(records)
  end
end
