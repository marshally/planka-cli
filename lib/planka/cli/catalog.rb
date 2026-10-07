require "planka/cli/resources"

module Planka
  module CLI
    # Combines resource commands and explicitly attached command catalogs.
    # Catalogs key commands and groups by their command paths: two or three
    # words, such as ["get", "card"] or ["workflow", "resume", "ticket"].
    class Catalog
      PATH_SIZES = [3, 2].freeze

      attr_reader :commands, :groups

      def initialize(legacy_commands:, extensions:)
        catalogs = [Resources, *extensions]
        @commands = catalogs.flat_map { |catalog| catalog.commands.to_a }.to_h
        @groups = catalogs.flat_map { |catalog| catalog.groups.to_a }.to_h
        @aliases = @commands.flat_map { |path, command|
          command.aliases.map { |alias_path| [alias_path, path] }
        }.to_h
        @root_help = [*catalogs.map(&:root_help), "Legacy commands (deprecated, retained indefinitely):\n",
                      "\ncommands: #{legacy_commands.join(", ")}\n\nRun planka <command> --help for command usage and options."].join
      end

      # The longest command path that prefixes args, so a three-word command
      # wins over a two-word command whose reference is the third word.
      def resolve(args)
        PATH_SIZES.each do |size|
          canonical = @aliases.fetch(args.first(size), args.first(size))
          return [canonical, @commands[canonical]] if @commands.key?(canonical)
        end
        [args.first(2), nil]
      end

      def group?(path) = @groups.key?(path)

      def help_text(args, command)
        return @root_help if args.empty?

        command ? command.help : @groups.fetch(args)
      end
    end
  end
end
