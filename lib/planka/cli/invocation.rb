require "optparse"
require "planka"
require "planka/cli/failure"

module Planka
  module CLI
    # Parses the command language; a parsed invocation selects a reader and formatter.
    class Invocation
      ROOT_HELP = <<~HELP
        usage: planka <verb> <resource> [reference] [flags]
        Administration:
          describe card CARD  Read card details and related data (read-only)
          describe board BOARD  Read board snapshot and related data (read-only)
        Workflows:
          workflow pending-criteria CARD  Read unfinished acceptance criteria (read-only)
        Legacy commands (deprecated, retained indefinitely):
      HELP
      GROUP_HELP = <<~HELP
        usage: planka describe <resource> REF [flags]
          card CARD  Read card details and related data (read-only)
          board BOARD  Read board snapshot and related data (read-only)
      HELP
      WORKFLOW_HELP = <<~HELP
        usage: planka workflow <operation> [arguments] [flags]
          pending-criteria CARD  Read unfinished acceptance criteria (read-only)
      HELP
      PENDING_CRITERIA_HELP = <<~HELP
        usage: planka workflow pending-criteria CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Prints unfinished tasks from lists named exactly "Acceptance criteria", in board-response order.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        JSON data has cardId and criteria; empty criteria are a successful empty array.
        Human output is one criterion per line. Failures exit 1 or 2.
        Example: planka workflow pending-criteria 123 -o json
      HELP
      LEAF_HELP = <<~HELP
        usage: planka describe card CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
        Example: planka describe card 123 -o json
      HELP

      BOARD_HELP = <<~HELP
        usage: planka describe board BOARD [--output human|json]
        Read-only: board ID or same-instance board URL; an explicit target is required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Human output matches snapshot. JSON uses data/meta/error; failures exit 1 or 2.
        Example: planka describe board 123 -o json
      HELP

      COMMANDS = {
        ["describe", "card"] => { resource: "card", collection: "cards", help: LEAF_HELP, reader: Planka::CardDetail, formatter: :card_detail }.freeze,
        ["describe", "board"] => { resource: "board", collection: "boards", help: BOARD_HELP, reader: Planka::Snapshot, formatter: :board_snapshot }.freeze,
        ["workflow", "pending-criteria"] => { resource: "card", collection: "cards", help: PENDING_CRITERIA_HELP, reader: Planka::PendingCriteria, formatter: :pending_criteria }.freeze,
      }.freeze
      GROUPS = { "describe" => GROUP_HELP, "workflow" => WORKFLOW_HELP }.freeze

      attr_reader :program, :output, :resource, :reference

      def self.parse(argv, legacy_commands:)
        new(argv, legacy_commands: legacy_commands).parse
      end

      def initialize(argv, legacy_commands:)
        @args = argv.dup
        @legacy_commands = legacy_commands
        @show_help = argv.empty?
        requested = argv.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
        requested = "json" if argv.include?("--output=json") || argv.include?("-ojson")
        @output = requested == "json" ? "json" : "human"
        @program = "planka"
        group = argv.find { |arg| GROUPS.key?(arg) }
        @program = "planka #{group}" if group
      end

      def parse
        @parser = OptionParser.new do |parser|
          parser.on("-o", "--output FORMAT", %w[human json]) do |value|
            invalid!("Conflicting output formats") if @seen_output && @seen_output != value
            @seen_output = @output = value
          end
          parser.on("-h", "--help") { @show_help = true }
        end
        @parser.parse!(@args)
        operation = @args[1].to_s
        operation = operation.delete_suffix("s") if @args.first == "describe"
        @command = COMMANDS[[@args.first, operation]]
        @resource = @command&.fetch(:resource)
        unless @args.empty? || (GROUPS.key?(@args.first) && (@args.size == 1 || @command))
          invalid!("unknown command; see planka --help")
        end
        @program = "planka #{@args.first} #{operation}" if @command
        invalid!("Unexpected arguments; see #{@program} --help") if @args.size > 3
        return self if help?

        unless @command && @args.size == 3
          invalid!("Expected a command and reference; see #{@program} --help")
        end
        @reference = @args.last
        unless @reference.match?(/\A\d+\z/) || @reference.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/#{collection}/\d+/?\z})
          invalid!("Expected a numeric #{@resource} ID or supported #{@resource} URL")
        end
        self
      rescue OptionParser::ParseError
        invalid!("Invalid option or output format; see #{@program} --help")
      end

      def help? = @show_help
      def collection = @command.fetch(:collection)
      def formatter = @command.fetch(:formatter)

      def help_text
        text = if @args.empty?
          [ROOT_HELP, "commands: #{@legacy_commands.join(', ')}",
            "\nRun planka <command> --help for command usage and options."].join("\n")
        elsif @args.size == 1
          GROUPS.fetch(@args.first)
        else
          @command.fetch(:help)
        end
        "#{text}\n#{@parser.help}"
      end

      def execute(client, target, base_url:)
        @command.fetch(:reader).read(client, target, base_url: base_url)
      end

      private

      def invalid!(message)
        raise Failure.new(code: "invalid_input", message: message, status: 2, program: @program, output: @output)
      end
    end
  end
end
