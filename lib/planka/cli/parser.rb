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
        # Arguments are UTF-8 text whatever the process locale.
        @args = argv.map { |arg| arg.dup.force_encoding(Encoding::UTF_8) }
        @flag_values = {}
        @show_help = argv.empty?
        requested = argv.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
        requested = "json" if argv.include?("--output=json") || argv.include?("-ojson")
        @output = requested == "json" ? "json" : "human"
        @program = "planka"
        group = argv.find { |arg| @catalog.group?([arg]) }
        @program = "planka #{group}" if group
      end

      def parse
        validate_encoding!
        parse_options!
        resolve_command!
        validate_flags!
        validate_extra_arguments!
        unless @show_help
          validate_required_arguments!
          parse_reference!
        end
        build_invocation
      rescue OptionParser::ParseError
        invalid!("Invalid option or output format; see #{@program} --help")
      end

      private

      def validate_encoding!
        invalid!("Arguments must be valid UTF-8") unless @args.all?(&:valid_encoding?)
      end

      def parse_options!
        parser_for(@catalog.commands.values).parse!(@args)
      end

      def resolve_command!
        @path, @command = @catalog.resolve(@args)
        invalid!("unknown command; see planka --help") unless @args.empty? || @command || @catalog.group?(@args)
        @program = "planka #{@path.join(" ")}" if @command
      end

      def validate_flags!
        allowed = @command ? @command.flag_keys : []
        invalid!("Unsupported flags; see #{@program} --help") unless (@flag_values.keys - allowed).empty?
        if @command&.optional_reference? && @args.size > @path.size &&
           !(@flag_values.keys & @command.collection_flags).empty?
          invalid!("Collection filters and limits require an omitted reference")
        end
        if @command && (message = @command.flag_error(@flag_values))
          invalid!(message)
        end
      end

      # A group path without a command is only valid with --help.
      def argument_count
        @command ? @path.size + (@command.reference? ? 1 : 0) : @args.size
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
        return if @command.optional_reference? && @args.size == @path.size

        @reference = @args.last
        if @command.names? && !@reference.strip.empty? && !@reference.match?(%r{\A(?:https?://|/|\.\./)})
          return
        end

        return if @reference.match?(/\A\d+\z/) || url_reference?

        resource = @command.resource
        invalid!(@command.url? ? "Expected a numeric #{resource} ID or supported #{resource} URL" : "Expected a numeric #{resource} ID or exact #{resource} name")
      end

      # Resources without a same-instance URL accept no URL form.
      def url_reference?
        @command.url? && @reference.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/#{@command.collection}/\d+/?\z})
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
        raise Failure.invalid_input(message, program: @program, output: @output)
      end
    end
  end
end
