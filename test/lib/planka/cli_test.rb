require_relative "planka_test_helper"
require "open3"
require "socket"
require "tmpdir"

require "rbconfig"

class Planka::CLITest < Minitest::Test
  include PlankaTestHelper

  ROOT = File.expand_path("../../..", __dir__)
  COMMANDS = %w[prime link next-card branch-name claim comment unticked spec-sweep loop-lock
                snapshot show create-list create-spec create-ticket update-card move-card labels
                create-label apply-label create-task-list rename-task-list].freeze

  def run_cli(*args, env: {}, executable: "planka")
    Open3.capture3({ "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil,
                     "PLANKA_AGENT_PASSWORD" => nil, "PLANKA_BOARD_ID" => nil,
                     "PLANKA_BRANCH_PREFIX" => nil }.merge(env),
                   RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args, chdir: Dir.tmpdir)
  end

  def test_nested_help_lists_only_implemented_canonical_commands
    [[], ["--help"], ["describe", "--help"], ["describe", "card", "-h"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "describe"
      assert_includes out, "card"
      refute_includes out, "create user"
    end
    out, = run_cli("describe", "card", "--help")
    assert_includes out, "planka describe card CARD"
    assert_includes out, "-o, --output"
  end

  def test_board_description_help_is_available_without_credentials
    [["--help"], ["describe", "--help"], ["describe", "board", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "board BOARD"
    end
    out, = run_cli("describe", "boards", "-h")
    assert_includes out, "planka describe board BOARD"
    assert_includes out, "PLANKA_AGENT_PASSWORD"
    assert_includes out, "-o, --output"
  end

  def test_root_help_with_common_output_flags_keeps_legacy_discoverability
    out, err, status = run_cli("-o", "json", "--help")
    assert status.success?, err
    assert_includes out, "next-card"
    assert_includes out, "planka <command> --help"
  end

  def test_workflow_help_is_offline_and_legacy_unticked_names_its_replacement
    [["--help"], ["workflow", "--help"], ["workflow", "pending-criteria", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "pending-criteria CARD"
      if args.size == 1
        assert_includes out, "workflow create ticket"
      elsif args == ["workflow", "--help"]
        assert_includes out, "create ticket"
      else
        refute_includes out, "create ticket"
      end
    end
    out, = run_cli("workflow", "pending-criteria", "--help")
    assert_includes out, "Acceptance criteria"
    assert_includes out, "-o, --output"
    out, err, status = run_cli("unticked", "--help")
    assert status.success?, err
    assert_includes out, "Deprecated"
    assert_includes out, "planka workflow pending-criteria CARD"
    direct, direct_err, direct_status = run_cli("--help", executable: "planka-unticked")
    assert direct_status.success?, direct_err
    assert_equal out, direct
  end

  def test_legacy_show_help_identifies_its_implemented_canonical_replacement
    out, err, status = run_cli("show", "--help")
    assert status.success?, err
    assert_includes out, "planka describe card CARD"
    direct, direct_err, direct_status = run_cli("--help", executable: "planka-show")
    assert direct_status.success?, direct_err
    assert_equal out, direct
  end

  def test_snapshot_help_names_the_board_replacement_and_keeps_list_arguments
    out, err, status = run_cli("snapshot", "--help")
    assert status.success?, err
    assert_includes out, "planka describe board BOARD"
    assert_includes out, "--list LIST"
    direct, direct_err, direct_status = run_cli("--help", executable: "planka-snapshot")
    assert direct_status.success?, direct_err
    assert_equal out, direct
  end

  def test_option_errors_use_the_documented_command_name_for_both_entry_points
    COMMANDS.each do |command|
      _out, err, status = run_cli(command, "--unknown")
      refute status.success?
      assert_match(/\Aplanka #{command}: invalid option: --unknown\n/, err)

      _out, direct_err, direct_status = run_cli("--unknown", executable: "planka-#{command}")
      refute direct_status.success?
      assert_equal err, direct_err
    end
  end

  def test_branch_name_workflow_help_is_offline_and_legacy_help_names_replacement
    [["--help"], ["workflow", "--help"], ["workflow", "branch-name", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "branch-name CARD"
    end
    out, = run_cli("workflow", "branch-name", "--help")
    assert_includes out, "PLANKA_BRANCH_PREFIX"
    assert_includes out, "-o, --output"
    out, err, status = run_cli("branch-name", "--help")
    assert status.success?, err
    assert_includes out, "planka workflow branch-name CARD"
    direct, direct_err, direct_status = run_cli("--help", executable: "planka-branch-name")
    assert direct_status.success?, direct_err
    assert_equal out, direct
  end

  def test_claim_status_help_is_offline_and_explains_its_scope
    [["--help"], ["workflow", "--help"], ["workflow", "claim-status", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "claim-status"
    end
    out, = run_cli("workflow", "claim-status", "--help")
    assert_includes out, "all accessible boards"
    assert_includes out, "does not acquire"
    assert_includes out, "no GitHub"
    assert_includes out, "PLANKA_AGENT_PASSWORD"
    dispatched, err, status = run_cli("loop-lock", "--help")
    assert status.success?, err
    assert_includes dispatched, "planka workflow claim-status"
    direct, err, status = run_cli("--help", executable: "planka-loop-lock")
    assert status.success?, err
    assert_equal dispatched, direct
  end

  def test_every_command_has_matching_help_through_both_entry_points
    COMMANDS.each do |command|
      out, err, status = run_cli(command, "--help")
      assert status.success?, "#{command}: #{err}"
      assert_empty err
      assert_match(/\Ausage: planka #{command}(?: |\n)/, out)
      assert_includes out, "--output FORMAT"
      assert_includes out, "Deprecated compatibility entry point; retained indefinitely."
      assert_includes out, "-h, --help"

      direct_out, direct_err, direct_status = run_cli("--help", executable: "planka-#{command}")
      assert direct_status.success?, direct_err
      assert_empty direct_err
      assert_equal out, direct_out

      short_out, short_err, short_status = run_cli(command, "-h")
      assert short_status.success?, short_err
      assert_equal out, short_out
    end
  end

  def test_version_and_help_need_no_credentials_or_checkout
    out, err, status = run_cli("--version")
    assert status.success?, err
    assert_equal "#{Planka::VERSION}\n", out
    out, err, status = run_cli("--help")
    assert status.success?, err
    assert_includes out, "next-card"
    assert_includes out, "planka <command> --help"
    short_out, short_err, short_status = run_cli("-h")
    assert short_status.success?, short_err
    assert_equal out, short_out
  end

  def test_leaf_help_lists_scope_flags_only_for_commands_that_accept_them
    [["describe", "board"], ["describe", "card"], ["workflow", "guide"], ["workflow", "pending-criteria"]].each do |args|
      out, err, status = run_cli(*args, "--help")
      assert status.success?, err
      refute_match(/^\s+--board BOARD/, out)
      refute_match(/^\s+--label LABEL/, out)
    end
  end

  def test_workflow_next_help_is_offline_and_explains_modes_scope_and_github
    [["--help"], ["workflow", "--help"], ["workflow", "next", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "next"
    end
    out, _, _ = run_cli("workflow", "next", "--help")
    %w[PLANKA_BOARD_ID --board --label feature: effort: gh read-only].each { |text| assert_includes out, text }
    assert_includes out, "AND"
    assert_includes out, "does not claim"
    assert_includes out, "Unknown"
    out, err, status = run_cli("next-card", "--help")
    assert status.success?, err
    assert_includes out, "planka workflow next"
    direct, err, status = run_cli("--help", executable: "planka-next-card")
    assert status.success?, err
    assert_equal out, direct
  end

  def test_workflow_guide_returns_canonical_json_without_credentials_or_checkout
    out, err, status = run_cli("workflow", "guide", "-o", "json")
    assert status.success?, err
    assert_empty err
    document = JSON.parse(out)
    assert_equal %w[data error meta], document.keys.sort
    assert_equal({}, document.fetch("meta"))
    assert_nil document.fetch("error")
    instructions = document.fetch("data").fetch("instructions")
    assert_match(/\A# planka-cli agent guide\n/, instructions)
    assert_includes instructions, "planka workflow guide"
    assert_includes instructions, "planka describe card CARD"
    assert_includes instructions, "planka workflow claim-status"
    assert_includes instructions, "planka workflow branch-name CARD"
    assert_includes instructions, "planka workflow pending-criteria CARD"
    assert_includes instructions, "planka workflow next --board BOARD"
    assert_includes instructions, "read the board back before retrying"
    assert_operator instructions.split.size, :<=, 500
  end

  def test_workflow_guide_help_and_legacy_prime_help_name_the_offline_replacement
    [["--help"], ["workflow", "--help"], ["workflow", "guide", "--help"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_includes out, "guide"
    end
    out, _, _ = run_cli("workflow", "guide", "--help")
    assert_includes out, "no credentials or network"
    assert_includes out, "instructions"
    assert_includes out, "-o, --output"
    out, err, status = run_cli("prime", "--help")
    assert status.success?, err
    assert_includes out, "planka workflow guide"
    direct, err, status = run_cli("--help", executable: "planka-prime")
    assert status.success?, err
    assert_equal out, direct
  end

  def test_workflow_guide_ignores_connection_settings_and_makes_no_network_requests
    server = TCPServer.new("127.0.0.1", 0)
    expected, err, status = run_cli("workflow", "guide")
    assert status.success?, err
    assert_empty err
    ["http://127.0.0.1:#{server.addr[1]}", "invalid-private-url"].each do |base|
      out, err, status = run_cli("workflow", "guide", env: {
                                   "PLANKA_BASE_URL" => base, "PLANKA_AGENT_EMAIL" => "private-guide@example.invalid",
                                   "PLANKA_AGENT_PASSWORD" => "private-guide-password", "PLANKA_BOARD_ID" => "private-board",
                                   "PLANKA_BRANCH_PREFIX" => "x" * 60
                                 })
      assert status.success?, err
      assert_empty err
      assert_equal expected, out
      refute_includes out, "private-guide"
      refute IO.select([server], nil, nil, 0), "guide must not open an authentication session"
    end
  ensure
    server&.close
  end

  def test_workflow_guide_human_and_json_formats_agree_with_flags_in_any_position
    human, err, status = run_cli("workflow", "guide")
    assert status.success?, err
    [["-o", "json", "workflow", "guide"], ["workflow", "-o", "json", "guide"],
     ["workflow", "guide", "--output=json"], ["workflow", "guide", "-ojson"]].each do |args|
      out, err, status = run_cli(*args)
      assert status.success?, err
      assert_empty err
      assert_equal human, JSON.parse(out).fetch("data").fetch("instructions")
    end
    out, err, status = run_cli("workflow", "guide", "-o", "human")
    assert status.success?, err
    assert_equal human, out
  end

  def test_workflow_guide_rejects_targets_and_unsupported_flags_with_canonical_errors
    [["extra"], ["extra", "--help"], ["--board", "123"], ["--limit", "1"],
     ["--unknown"], ["--output", "yaml"], ["--output", "human"]].each do |suffix|
      out, err, status = run_cli("-o", "json", "workflow", "guide", *suffix)
      assert_equal 2, status.exitstatus, err
      document = JSON.parse(out)
      assert_nil document.fetch("data")
      assert_equal({}, document.fetch("meta"))
      assert_equal "invalid_input", document.fetch("error").fetch("code")
      assert_match(/\Aplanka workflow(?: guide)?: /, err)
      refute_includes err, "PLANKA_AGENT_PASSWORD"
      refute_includes err, "configuration_error"
    end
  end

  def test_prime_teaches_the_agent_workflow_without_credentials_or_checkout
    out, err, status = run_cli("prime")
    assert status.success?, err
    assert_empty err
    assert_match(/\A# planka-cli agent guide\n/, out)
    assert_includes out, "--output json"
    assert_includes out, "PLANKA_BASE_URL"
    assert_includes out, "PLANKA_AGENT_EMAIL"
    assert_includes out, "PLANKA_AGENT_PASSWORD"
    assert_includes out, "PLANKA_BOARD_ID"
    assert_includes out, "planka next-card"
    assert_includes out, "planka show CARD"
    assert_includes out, "planka claim CARD"
    assert_includes out, "planka link BLOCKED BLOCKER"
    assert_includes out, "planka create-ticket --card CARD"
    assert_includes out, "read the board back before retrying"
    assert_includes out, "planka <command> --help"
    assert_operator out.split.size, :<=, 500, "primer should fit a small agent context budget"
  end

  def test_prime_json_contains_the_same_instructions
    human, err, status = run_cli("prime")
    assert status.success?, err

    out, err, status = run_cli("prime", "--output", "json")
    assert status.success?, err
    assert_empty err
    assert_equal({ "instructions" => human }, JSON.parse(out))
  end

  def test_prime_rejects_unexpected_positional_arguments
    out, err, status = run_cli("prime", "extra")
    refute status.success?
    assert_empty out
    assert_includes err, "usage: planka prime [--output human|json]"
  end

  def test_direct_prime_is_independent_of_connection_settings_and_keeps_credentials_private
    expected, err, status = run_cli("prime", "--output", "json")
    assert status.success?, err
    out, err, status = run_cli("--output", "json", executable: "planka-prime", env: {
                                 "PLANKA_BASE_URL" => "http://127.0.0.1:1",
                                 "PLANKA_AGENT_EMAIL" => "private-agent@example.invalid",
                                 "PLANKA_AGENT_PASSWORD" => "private-prime-test-password",
                                 "PLANKA_BOARD_ID" => "private-board-id",
                               })
    assert status.success?, err
    assert_empty err
    assert_equal expected, out
    refute_includes out, "private-prime-test-password"
    refute_includes out, "private-agent@example.invalid"
    refute_includes out, "private-board-id"
  end

  def test_unknown_command_and_missing_credentials_fail_clearly
    _out, err, status = run_cli("unknown")
    refute status.success?
    assert_includes err, "unknown command"
    _out, err, status = run_cli("branch-name", "123")
    refute status.success?
    assert_match(/\Aplanka branch-name: /, err)
    assert_includes err, "PLANKA_BASE_URL"
    refute_includes err, ".mcp.json"
    _out, err, status = run_cli("show", "123")
    refute status.success?
    assert_match(/\Aplanka show: /, err)
    assert_includes err, "PLANKA_BASE_URL"
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
    assert_equal "https://other.example/planka/cards/#{card_id("Contract edits")}",
                 custom.card(card_id("Contract edits")).url
  end

  def test_branch_prefix_is_optional_and_configurable
    card = Struct.new(:name, :features).new("A very long card name " * 10, [])
    assert_operator Planka::Workflow::BranchName.for(card, prefix: "").length, :<=, 63
    assert_operator Planka::Workflow::BranchName.for(card, prefix: "another-project-").length, :<=, 47
    single_word = Struct.new(:name, :features).new("x" * 100, [])
    assert_equal "card/" + "x" * 58, Planka::Workflow::BranchName.for(single_word, prefix: "")
    assert_raises(Planka::Error) { Planka::Workflow::BranchName.for(card, prefix: "x" * 60) }
  end

  def test_next_card_signs_in_reads_configured_board_and_signs_out
    server = TCPServer.new("127.0.0.1", 0)
    base = "http://127.0.0.1:#{server.addr[1]}"
    requests = []
    add_label("effort:extract", card_id("Contract edits"))
    worker = Thread.new do
      responses = [{ "item" => "test-token" }, { "included" => payload }, {}]
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
                                 "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "test-password"
                               })
    assert worker.join(5), "HTTP worker did not finish"
    worker.value
    assert status.success?, err
    assert_includes out, "#{base}/cards/#{card_id("Contract edits")}"
    assert_equal [["POST", "/api/access-tokens"], ["GET", "/api/boards/custom-board"],
                  ["DELETE", "/api/access-tokens/me"]], requests.map(&:first)
    assert_equal "Bearer test-token", requests[1][1]
    assert_equal "bot@example.com", JSON.parse(requests[0][2]).fetch("emailOrUsername")
  ensure
    server&.close
    worker&.kill if worker&.alive?
  end
end
