require "optparse"
require "planka"
require "planka/cli/failure"
require "planka/cli"

module Planka
  module CLI
    # Parses the command language; a parsed invocation selects a reader and formatter.
    class Invocation
      ROOT_HELP = <<~HELP
        usage: planka <verb> <resource> [reference] [flags]
        Administration:
          describe card CARD  Read card details and related data (read-only)
          describe board BOARD  Read board snapshot and related data (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka describe <resource> REF [flags]
          card CARD  Read card details and related data (read-only)
          board BOARD  Read board snapshot and related data (read-only)
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
        ["describe", "card"] => { resource: "card", collection: "cards", help: LEAF_HELP, reader: Planka::CardDetail, formatter: Planka::CLI.method(:card_detail) }.freeze,
        ["describe", "board"] => { resource: "board", collection: "boards", help: BOARD_HELP, reader: Planka::Snapshot, formatter: Planka::CLI.method(:board_snapshot) }.freeze,
      }.freeze
      GROUPS = { "describe" => GROUP_HELP }.freeze

      attr_reader :program, :output, :resource, :reference

      def self.parse(argv, legacy_commands:, extensions: [])
        new(argv, legacy_commands: legacy_commands, extensions: extensions).parse
      end

      def initialize(argv, legacy_commands:, extensions:)
        @commands = COMMANDS.merge(extensions.flat_map { |extension| extension.commands.to_a }.to_h)
        @groups = GROUPS.merge(extensions.flat_map { |extension| extension.groups.to_a }.to_h)
        @root_help = [ROOT_HELP, *extensions.map(&:root_help), "Legacy commands (deprecated, retained indefinitely):\n"]
        @args = argv.dup
        @flag_values = {}
        @legacy_commands = legacy_commands
        @show_help = argv.empty?
        requested = argv.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
        requested = "json" if argv.include?("--output=json") || argv.include?("-ojson")
        @output = requested == "json" ? "json" : "human"
        @program = "planka"
        group = argv.find { |arg| @groups.key?(arg) }
        @program = "planka #{group}" if group
      end

      def parse
        @parser = parser_for(@commands.values)
        @parser.parse!(@args)
        operation = @args[1].to_s
        operation = operation.delete_suffix("s") if @args.first == "describe"
        @command = @commands[[@args.first, operation]]
        @resource = @command && @command[:resource]
        unless @args.empty? || (@groups.key?(@args.first) && (@args.size == 1 || @command))
          invalid!("unknown command; see planka --help")
        end
        @program = "planka #{@args.first} #{operation}" if @command
        allowed = @command ? @command.fetch(:flags, {}).values : []
        invalid!("Unsupported flags; see #{@program} --help") unless (@flag_values.keys - allowed).empty?
        if @command && (message = @command[:validate_flags]&.call(@flag_values))
          invalid!(message)
        end
        argument_count = @command && !@command.fetch(:reference, true) ? 2 : 3
        invalid!("Unexpected arguments; see #{@program} --help") if @args.size > argument_count
        return self if help?

        unless @command && @args.size == argument_count
          invalid!("Expected a command and reference; see #{@program} --help")
        end
        return self unless @command.fetch(:reference, true)

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
      def json_data(result) = @command[:projector] ? @command[:projector].call(result) : result
      def requires_session? = @command.fetch(:session, true)

      def help_text
        text = if @args.empty?
          [@root_help.join, "commands: #{@legacy_commands.join(', ')}",
            "\nRun planka <command> --help for command usage and options."].join("\n")
        elsif @args.size == 1
          @groups.fetch(@args.first)
        else
          @command.fetch(:help)
        end
        "#{text}\n#{parser_for([@command].compact).help}"
      end

      def reader_options(configuration, env:)
        options = { base_url: configuration.base_url }
        options.merge!(@command[:options].call(env, configuration: configuration, flags: @flag_values)) if @command[:options]
        options
      end

      def execute(client = nil, target = nil, **options)
        arguments = if requires_session?
          @command.fetch(:reference, true) ? [client, target] : [client]
        else
          []
        end
        @command.fetch(:reader).read(*arguments, **options)
      end

      private

      def parser_for(commands)
        OptionParser.new do |parser|
          parser.on("-o", "--output FORMAT", %w[human json]) do |value|
            invalid!("Conflicting output formats") if @seen_output && @seen_output != value
            @seen_output = @output = value
          end
          parser.on("-h", "--help") { @show_help = true }
          commands.flat_map { |command| command.fetch(:flags, {}).to_a }.uniq.each do |syntax, key|
            parser.on(syntax) { |value| (@flag_values[key] ||= []) << value }
          end
        end
      end

      def invalid!(message)
        raise Failure.new(code: "invalid_input", message: message, status: 2, program: @program, output: @output)
      end
    end
  end
end
