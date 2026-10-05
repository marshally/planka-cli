require_relative "planka_test_helper"

class Planka::ClientTest < Minitest::Test
  def test_a_rejected_or_unsent_request_left_planka_unchanged
    assert Planka::Client.unapplied?(Planka::Client::HTTPError.new("409", 409))
    assert Planka::Client.unapplied?(Errno::ECONNREFUSED.new)
    assert Planka::Client.unapplied?(Net::OpenTimeout.new)
  end

  def test_a_request_lost_after_sending_may_have_applied
    refute Planka::Client.unapplied?(Net::ReadTimeout.new)
    refute Planka::Client.unapplied?(Errno::ECONNRESET.new)
    refute Planka::Client.unapplied?(Planka::Client::ServerError.new("502"))
  end
end
