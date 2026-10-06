require_relative "planka_test_helper"

class Planka::RecordsTest < Minitest::Test
  def test_an_id_is_a_numeric_string
    assert Planka::Records.id?("123")
    refute Planka::Records.id?(123)
    refute Planka::Records.id?("12a")
    refute Planka::Records.id?("")
  end

  def test_a_timestamp_is_an_iso8601_string
    assert Planka::Records.timestamp?("2026-09-01T00:00:00.000Z")
    refute Planka::Records.timestamp?("yesterday")
    refute Planka::Records.timestamp?(nil)
  end

  def test_a_signed_in_user_needs_a_nonempty_id
    user = { "id" => "7" }

    assert_same user, Planka::Records.user!(user)
    [nil, {}, { "id" => "" }, { "id" => 7 }].each do |invalid|
      error = assert_raises(Planka::InvalidResponse) { Planka::Records.user!(invalid) }
      assert_equal "Invalid signed-in user", error.message
    end
  end
end
