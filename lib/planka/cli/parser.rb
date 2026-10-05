require "optparse"
require "planka/cli/catalog"
require "planka/cli/invocation"
require "planka/cli/failure"

module Planka
  module CLI
    # Mutable parsing state ends when an immutable Invocation is returned.
    class Parser
      def self.parse(argv, legacy_commands:, extensions: [])
        new(argv, legacy_commands: legacy_commands, extensions: extensions).parse
      end

      def initialize(argv, legacy_commands:, extensions:)
        @catalog = Catalog.new(legacy_commands: legacy_commands, extensions: extensions)
        @args = argv.dup
        @flag_values = {}
        @show_help = argv.empty?
        requested = argv.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
        requested = "json" if argv.include?("--output=json") || argv.include?("-ojson")
        @output = requested == "json" ? "json" : "human"
        @program = "planka"
        group = argv.find { |arg| @catalog.groups.key?(arg) }
        @program = "planka #{group}" if group
      end

      def parse
        @parser = parser_for(@catalog.commands.values)
        @parser.parse!(@args)
        path, @command = @catalog.resolve(@args.first(2))
        @resource = @command && @command[:resource]
        unless @args.empty? || (@catalog.groups.key?(@args.first) && (@args.size == 1 || @command))
          invalid!("unknown command; see planka --help")
        end
        @program = "planka #{path.join(' ')}" if @command
        allowed = @command ? @command.fetch(:flags, {}).values : []
        invalid!("Unsupported flags; see #{@program} --help") unless (@flag_values.keys - allowed).empty?
        if @command && (message = @command[:validate_flags]&.call(@flag_values))
          invalid!(message)
        end
        argument_count = @command && !@command.fetch(:reference, true) ? 2 : 3
        invalid!("Unexpected arguments; see #{@program} --help") if @args.size > argument_count
        return invocation if @show_help

        unless @command && @args.size == argument_count
          invalid!("Expected a command and reference; see #{@program} --help")
        end
        return invocation unless @command.fetch(:reference, true)

        @reference = @args.last
        unless @reference.match?(/\A\d+\z/) || @reference.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/#{@command.fetch(:collection)}/\d+/?\z})
          invalid!("Expected a numeric #{@resource} ID or supported #{@resource} URL")
        end
        invocation
      rescue OptionParser::ParseError
        invalid!("Invalid option or output format; see #{@program} --help")
      end

      private

      def invocation
        help_text = "#{@catalog.help_text(@args, @command)}\n#{parser_for([@command].compact).help}" if @show_help
        Invocation.new(program: @program, output: @output, command: @command,
          reference: @reference, flags: @flag_values, help_text: help_text)
      end

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
