require "planka"
require "planka/cli/command"
require "planka/cli/failure"
require "planka/cli/resources/board_scope"

module Planka
  module CLI
    module Resources
      module Lists
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          get lists --board BOARD  List a board's lists of every type (read-only)
          get list LIST  Read one board list (read-only)
        HELP
        COMMON_HELP = <<~HELP
          LIST is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID. A list ID
          alone finds its own board for active/closed lists, while archive/trash lists need --board.
          Explicit list IDs/URLs ignore the default board; --board asserts the actual parent.
          Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Success exits 0, local input 2, operational failures 1. list/lists are aliases.
          List data: id, name, type, color, boardId, position, createdAt, updatedAt.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get lists --board BOARD [--name NAME] [--limit N] [-o human|json]
                 planka get list LIST [--board BOARD] [-o human|json]
          Read-only. Without LIST, read every list on BOARD from one board read (no paging): active/closed
          lists by position, then archive and trash lists, which may be unnamed. --board is required;
          PLANKA_BOARD_ID is not a collection scope. An exact --name matches before a positive --limit;
          filters and limits require an omitted LIST. Collection data is an array with meta.complete, false
          when truncated or the read fails.
          With LIST, data is one list object and meta is empty.
        HELP
        GROUP_HELP = {
          "get" => "  lists --board BOARD  List a board's lists of every type (read-only)\n  list LIST  Read one board list (read-only)\n",
        }.freeze

        # get reads one list with a reference, otherwise the board's lists.
        def self.prepare_get(env, instance:, flags:, reference:)
          return prepare_list(env, instance: instance, flags: flags, reference: reference) if reference
          raise Failure.new(code: "invalid_input", status: 2, message: "get lists requires --board") unless flags[:board]

          { board_id: BoardScope.resolve(instance, flags[:board].first), name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
        end

        def self.prepare_list(env, instance:, flags:, reference:)
          { board_id: BoardScope.for_reference(env, instance, reference, flags[:board]&.first, resource: "List") }
        end

        def self.get(client, reference = nil, board_id: nil, **collection)
          lists = Planka::Boards::Lists.new(client, board_id: board_id)
          reference ? lists.find(reference) : lists.all(**collection)
        end

        def self.format_list(list) = "#{list["name"] || "(unnamed)"} (#{list["id"]}) #{list["type"]} on board #{list["boardId"]}"

        def self.format_lists(data)
          return format_list(data) if data.is_a?(Hash)

          data.empty? ? "No lists." : data.map { |list| format_list(list) }.join("\n")
        end

        COMMANDS = {
          ["get", "list"] => Command.new(aliases: [["get", "lists"]], names: true, optional_reference: true, collection_read: true,
                                         resource: "list", collection: "lists", collection_flags: [:name, :limit],
                                         flags: { "--board BOARD" => :board, "--name NAME" => :name, "--limit N" => :limit },
                                         validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare_get),
                                         help: GET_HELP, operation: method(:get), formatter: method(:format_lists)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
