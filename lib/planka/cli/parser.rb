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
        parse_options!
        resolve_command!
        validate_flags!
        validate_extra_arguments!
        unless @show_help
          validate_required_arguments!
          parse_reference!
          validate_inputs!
        end
        build_invocation
      rescue OptionParser::ParseError
        invalid!("Invalid option or output format; see #{@program} --help")
      end

      private

      def parse_options!
        parser_for(@catalog.commands.values).parse!(@args)
      end

      def resolve_command!
        path, @command = @catalog.resolve(@args.first(2))
        unless @args.empty? || (@catalog.groups.key?(@args.first) && (@args.size == 1 || @command))
          invalid!("unknown command; see planka --help")
        end
        @program = "planka #{path.join(" ")}" if @command
      end

      def validate_flags!
        allowed = @command ? @command.flag_keys : []
        invalid!("Unsupported flags; see #{@program} --help") unless (@flag_values.keys - allowed).empty?
        if @command&.optional_reference? && @args.size > 2 &&
           !(@flag_values.keys & @command.collection_flags).empty?
          invalid!("Collection filters and limits require an omitted reference")
        end
        if @command && (message = @command.flag_error(@flag_values))
          invalid!(message)
        end
      end

      def validate_inputs!
        message = @command.input_error(@reference, @flag_values)
        invalid!(message) if message
      end

      def argument_count
        @command && !@command.reference? ? 2 : 3
      end

      def validate_extra_arguments!
        invalid!("Unexpected arguments; see #{@program} --help") if @args.size > argument_count
      end

      def validate_required_arguments!
        minimum = @command&.optional_reference? ? argument_count - 1 : argument_count
        unless @command && @args.size >= minimum
          invalid!("Expected a command and reference; see #{@program} --help")
        end
      end

      def parse_reference!
        return unless @command.reference?
        return if @command.optional_reference? && @args.size == 2

        @reference = @args.last
        if @command.names? && !@reference.strip.empty? && !@reference.match?(%r{\A(?:https?://|/|\.\./)})
          return
        end

        collections = Array(@command.collection).map { |path| Regexp.escape(path) }.join("|")
        unless @reference.match?(/\A\d+\z/) || @reference.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/(?:#{collections})/\d+/?\z})
          resource = @command.resource
          invalid!("Expected a numeric #{resource} ID or supported #{resource} URL")
        end
      end

      def build_invocation
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
          commands.flat_map { |command| command.flags.to_a }.uniq.each do |syntax, key|
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
