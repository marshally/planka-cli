require "json"
require "optparse"

module Planka
  # Shared command plumbing: human-readable output by default, stable JSON on
  # stdout with --output json, diagnostics on stderr, and a nonzero exit when
  # anything fails. Partial creates retain their recovery state in JSON mode.
  module CLI
    module_function

    def emit(data, output:, human:)
      $stdout.puts(output == "json" ? JSON.generate(data) : human)
    end

    def labels(document)
      labels = Array(document["labels"])
      return "No labels" if labels.empty?

      labels.map { |label| "#{label["name"]} [#{label["color"]}] (#{label["id"]})" }.join("\n")
    end

    def resource_result(action, kind, record)
      name = record["name"] || record["id"]
      details = [ record["url"], ("ID: #{record["id"]}" if record["id"] && name != record["id"]) ].compact
      "#{action} #{kind}: #{name}#{details.empty? ? "" : " (#{details.join(", ")})"}"
    end

    def label_application(result)
      if result["created"]
        "Applied label #{result["labelId"]} to card #{result["cardId"]}"
      else
        "Card #{result["cardId"]} already has label #{result["labelId"]}"
      end
    end

    def output_option(parser, options)
      options[:output] = "human"
      parser.separator "Deprecated compatibility entry point; retained indefinitely."
      parser.on("--output FORMAT", %w[human json], "output format: human or json (default human)") do |format|
        options[:output] = format
      end
      parser.on("-h", "--help", "show command usage and options") do
        puts parser.help
        exit 0
      end
    end

    def output_parser(options, banner)
      OptionParser.new do |parser|
        parser.banner = banner
        output_option(parser, options)
      end
    end

    # A description or request body from a file, or from stdin when the path is
    # "-", or nil when no path was given.
    def source(path)
      return nil if path.nil?

      path == "-" ? $stdin.read : File.read(path)
    end

    def board_id(explicit) = explicit || ENV.fetch("PLANKA_BOARD_ID")

    # A list given as a numeric id is used as is; otherwise it is a name resolved
    # within the given board, which rejects an unknown or ambiguous name.
    def resolve_list(client, list, board)
      return list if list.to_s.match?(/\A\d+\z/)

      Planka::Board.new(client.board(board_id(board))).list_id(list)
    end

    # A position after every card currently in the list, so new work lands below
    # the existing queue.
    def append_position(client, list_id)
      Position.after(Array(client.list_cards(list_id)["items"]))
    end

    # Parses options, reporting a bad flag on stderr with the command's help
    # rather than a backtrace. Help exits before a client session is opened.
    def parse!(parser, program)
      parser.parse!
    rescue OptionParser::ParseError => e
      warn "#{program}: #{e.message}"
      warn parser.help
      exit 1
    end

    def run(program, output: "human")
      Planka::Client.session { |client| yield client }
    rescue Planka::PartialFailure => e
      document = e.state.merge("completed" => false, "error" => e.message)
      emit(document, output:, human: "Operation incomplete: #{e.message}\nCreated resources are available with --output json; resume rather than retrying the create.")
      warn "#{program}: #{e.message}"
      exit 1
    rescue Planka::Client::UnknownOutcome => e
      reconcile = "read the board back before retrying; the change may already have applied"
      emit({ "completed" => false, "error" => e.message, "reconcile" => reconcile },
        output:, human: "Outcome unknown: #{e.message}\n#{reconcile}")
      warn "#{program}: #{e.message}"
      exit 1
    rescue Planka::Error, KeyError, Errno::ENOENT, JSON::ParserError, SystemCallError => e
      warn "#{program}: #{e.message}"
      exit 1
    end
  end
end
