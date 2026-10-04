require "minitest/autorun"
require "open3"
require "rbconfig"
require "json"
require "tmpdir"

class PlankaLoadingTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_core_and_workflows_can_be_loaded_without_cli_or_environment_settings
    script = <<~RUBY
      require "planka"
      client = Planka::Client.new("https://planka.example")
      abort "Core loaded workflows" if defined?(Planka::Workflow)
      abort "Core loaded CLI" if defined?(Planka::CLI)
      included = JSON.parse(File.read(ARGV.fetch(0))).fetch("included")
      board = Planka::Board.new(included, base_url: "https://planka.example")
      card = board.cards.find { |record| record.name.start_with?("Contract edits") }
      require "planka/workflow"
      abort "Workflow loaded CLI" if defined?(Planka::CLI)
      workflow_card = Planka::Workflow::Board.new(board).card(card.id)
      puts JSON.generate({"client" => client.class.name, "ticket" => workflow_card.ticket?,
        "branch" => Planka::Workflow::BranchName.for(workflow_card, prefix: "lucenta-")})
    RUBY
    env = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD PLANKA_BOARD_ID PLANKA_BRANCH_PREFIX].to_h { |key| [key, nil] }
    out, err, status = Open3.capture3(env, RbConfig.ruby, "-w", "-I#{ROOT}/lib", "-e", script,
      "#{ROOT}/test/fixtures/files/planka/board.json", chdir: Dir.tmpdir)
    assert status.success?, err
    assert_empty err
    assert_equal({ "client" => "Planka::Client", "ticket" => true,
      "branch" => "feature/workspaces-contract-edits-by-direct-request" }, JSON.parse(out))
  end
end
