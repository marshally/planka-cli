require "json"

module Planka
  # Shared plumbing for the publishing commands: JSON on stdout, diagnostics on
  # stderr, and a nonzero exit when anything fails. A partial multi-step create
  # still prints the ids it got to so the caller can resume; a create whose
  # outcome is unknown prints a hint to reconcile by reading the board back.
  module CLI
    module_function

    def emit(data) = $stdout.puts(JSON.generate(data))

    # A description or request body from a file, or from stdin when the path is
    # "-", or nil when no path was given.
    def source(path)
      return nil if path.nil?

      path == "-" ? $stdin.read : File.read(path)
    end

    def board_id(explicit) = explicit || ENV.fetch("PLANKA_BOARD_ID")

    POSITION_GAP = 65_536

    # A list given as a numeric id is used as is; otherwise it is a name resolved
    # within the given board, which rejects an unknown or ambiguous name.
    def resolve_list(client, list, board)
      return list if list.to_s.match?(/\A\d+\z/)

      Planka::Board.new(client.board(board_id(board))).list_id(list)
    end

    # A position after every card currently in the list, so new work lands below
    # the existing queue.
    def append_position(client, list_id)
      cards = Array(client.list_cards(list_id)["items"])
      (cards.map { |card| card["position"].to_f }.max || 0) + POSITION_GAP
    end

    # Parses options, reporting a bad flag on stderr with the command's help
    # rather than a backtrace. --help is handled by OptionParser itself.
    def parse!(parser, program)
      parser.parse!
    rescue OptionParser::ParseError => e
      warn "#{program}: #{e.message}"
      warn parser.help
      exit 1
    end

    def run(program)
      Planka::Client.session { |client| yield client }
    rescue Planka::PartialFailure => e
      emit(e.state.merge("completed" => false, "error" => e.message))
      warn "#{program}: #{e.message}"
      exit 1
    rescue Planka::Client::UnknownOutcome => e
      emit("completed" => false, "error" => e.message,
        "reconcile" => "read the board back before retrying; the change may already have applied")
      warn "#{program}: #{e.message}"
      exit 1
    rescue Planka::Error, KeyError, Errno::ENOENT, JSON::ParserError, SystemCallError => e
      warn "#{program}: #{e.message}"
      exit 1
    end
  end
end
