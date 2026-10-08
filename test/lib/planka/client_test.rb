require "socket"
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

  # Canonical sessions reject malformed documents near the request; legacy
  # sessions keep their original fetch and JSON parse failures.
  def test_legacy_sessions_keep_fetch_and_parse_failures_for_malformed_documents
    with_body("{}") do |client|
      assert_raises(KeyError) { client.board("1") }
      assert_raises(KeyError) { client.me }
      assert_raises(KeyError) { client.create_card("1", name: "x") }
    end
    with_body("[]") { |client| assert_raises(TypeError) { client.board("1") } }
    with_body("not json") { |client| assert_raises(JSON::ParserError) { client.card("1") } }
  end

  def test_canonical_sessions_reject_malformed_documents
    with_body("{}", validate_responses: true) do |client|
      { board: ["1"], board_document: ["1"], list: ["1"], comments: ["1"], me: [], board_ids: [],
        move_card: %w[1 2], create_card: ["1"] }.each do |method, args|
        assert_raises(Planka::InvalidResponse, method.to_s) { client.public_send(method, *args) }
      end
      assert_raises(Planka::InvalidResponse) { client.sign_in("agent@example.test", "secret") }
    end
    with_body("[]", validate_responses: true) { |client| assert_raises(Planka::InvalidResponse) { client.card("1") } }
    with_body("not json", validate_responses: true) { |client| assert_raises(Planka::InvalidResponse) { client.card("1") } }
  end

  def test_canonical_sessions_accept_well_formed_documents
    document = { "item" => { "id" => "1" }, "items" => [], "included" => { "boards" => [{ "id" => "2" }] } }
    with_body(JSON.generate(document), validate_responses: true) do |client|
      assert_equal({ "id" => "1" }, client.me)
      assert_equal ["2"], client.board_ids
      assert_equal [], client.comments("1")
    end
  end

  private

  # A client whose local server answers every request with BODY.
  def with_body(body, validate_responses: false)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        socket = server.accept
        headers = []
        while (line = socket.gets) && line != "\r\n"
          headers << line
        end
        length = headers.find { |header| header.downcase.start_with?("content-length:") }.to_s.split(":").last.to_i
        socket.read(length)
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
                     "Connection: close\r\n\r\n#{body}")
        socket.close
      end
    rescue IOError
      nil
    end
    yield Planka::Client.new("http://127.0.0.1:#{server.addr[1]}", validate_responses: validate_responses)
  ensure
    server&.close
    thread&.join(2)
  end
end
