require_relative "planka_test_helper"
require "open3"
require "socket"
require "tmpdir"

require "rbconfig"

class Planka::CLITest < Minitest::Test
  include PlankaTestHelper

  ROOT = File.expand_path("../../..", __dir__)

  def run_cli(*args, env: {})
    Open3.capture3({ "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil,
      "PLANKA_AGENT_PASSWORD" => nil, "PLANKA_BOARD_ID" => nil,
      "PLANKA_BRANCH_PREFIX" => nil }.merge(env),
      RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/planka", *args, chdir: Dir.tmpdir)
  end

  def test_version_and_help_need_no_credentials_or_checkout
    out, err, status = run_cli("--version")
    assert status.success?, err
    assert_equal "#{Planka::VERSION}\n", out
    out, err, status = run_cli("--help")
    assert status.success?, err
    assert_includes out, "next-card"
  end

  def test_unknown_command_and_missing_credentials_fail_clearly
    _out, err, status = run_cli("unknown")
    refute status.success?
    assert_includes err, "unknown command"
    _out, err, status = run_cli("branch-name", "123")
    refute status.success?
    assert_includes err, "PLANKA_BASE_URL"
    refute_includes err, ".mcp.json"
  end

  def test_commands_document_and_validate_output_formats_without_credentials
    out, err, status = run_cli("show", "--help")
    assert status.success?, err
    assert_includes out, "--output FORMAT"
    assert_includes out, "human or json"

    _out, err, status = run_cli("show", "123", "--output", "yaml")
    refute status.success?
    assert_includes err, "invalid argument"
    assert_includes err, "--output"
  end

  def test_card_urls_use_the_board_instance_and_strip_trailing_slashes
    custom = Planka::Board.new(payload, base_url: "https://other.example/planka///")
    assert_equal "https://other.example/planka/cards/#{card_id('Contract edits')}",
      custom.card(card_id("Contract edits")).url
  end

  def test_branch_prefix_is_optional_and_configurable
    card = Struct.new(:name, :features).new("A very long card name " * 10, [])
    assert_operator Planka::BranchName.for(card, prefix: "").length, :<=, 63
    assert_operator Planka::BranchName.for(card, prefix: "another-project-").length, :<=, 47
    single_word = Struct.new(:name, :features).new("x" * 100, [])
    assert_equal "card/" + "x" * 58, Planka::BranchName.for(single_word, prefix: "")
    assert_raises(Planka::Error) { Planka::BranchName.for(card, prefix: "x" * 60) }
  end

  def test_next_card_signs_in_reads_configured_board_and_signs_out
    server = TCPServer.new("127.0.0.1", 0)
    base = "http://127.0.0.1:#{server.addr[1]}"
    requests = []
    add_label("effort:extract", card_id("Contract edits"))
    worker = Thread.new do
      responses = [ { "item" => "test-token" }, { "included" => payload }, {} ]
      responses.each do |response|
        socket = server.accept
        line = socket.gets
        headers = {}
        while (header = socket.gets) != "\r\n"
          key, value = header.split(":", 2)
          headers[key.downcase] = value.strip
        end
        body = socket.read(headers.fetch("content-length", "0").to_i)
        requests << [line.split.first(2), headers["authorization"], body]
        json = JSON.generate(response)
        socket.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}"
        socket.close
      end
    end
    # An effort query needs no GitHub or per-card comment calls.
    out, err, status = run_cli("next-card", "effort:extract", env: {
      "PLANKA_BASE_URL" => base, "PLANKA_BOARD_ID" => "custom-board",
      "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "test-password" })
    assert worker.join(5), "HTTP worker did not finish"
    worker.value
    assert status.success?, err
    assert_includes out, "#{base}/cards/#{card_id('Contract edits')}"
    assert_equal [ ["POST", "/api/access-tokens"], ["GET", "/api/boards/custom-board"],
      ["DELETE", "/api/access-tokens/me"] ], requests.map(&:first)
    assert_equal "Bearer test-token", requests[1][1]
    assert_equal "bot@example.com", JSON.parse(requests[0][2]).fetch("emailOrUsername")
  ensure
    server&.close
    worker&.kill if worker&.alive?
  end
end
