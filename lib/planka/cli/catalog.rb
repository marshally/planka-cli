require "planka/cli/resources"

module Planka
  module CLI
    # Combines resource commands and explicitly attached command catalogs.
    class Catalog
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

      def resolve(path)
        canonical = @aliases.fetch(path, path)
        [canonical, @commands[canonical]]
      end

      def help_text(args, command)
        return @root_help if args.empty?
        return @groups.fetch(args.first) if args.size == 1

        command.help
      end
    end
  end
end
