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

    def ticket_result(result)
      "#{resource_result("Created", "ticket", result.fetch("card"))}\nAcceptance criteria: #{Array(result["tasks"]).size}"
    end

    def label_application(result)
      if result["created"]
        "Applied label #{result["labelId"]} to card #{result["cardId"]}"
      else
        "Card #{result["cardId"]} already has label #{result["labelId"]}"
      end
    end

    def card_ref(card) = { "id" => card.id, "name" => card.name, "url" => card.url }

    def next_card(report)
      case report
      when Planka::NextCard::Pick
        {
          "card" => card_ref(report.card),
          "specs" => report.spec.map { |card| card_ref(card) },
          "number" => report.nn,
          "blockers" => report.blockers.map { |blocker| blocker_ref(blocker) },
          "parent" => Planka::Blocker.parent_branch(report.blockers),
        }
      when Planka::NextCard::Waiting
        {
          "card" => nil,
          "waiting" => report.cards.map do |card|
            card_ref(card).merge("claimed" => card.claimed?, "blockedBy" => card.open_blockers.map { |blocker| card_ref(blocker) })
          end,
        }
      when Planka::NextCard::FrontierReport
        {
          "card" => report.frontier.first && card_ref(report.frontier.first),
          "maps" => report.maps.map { |card| card_ref(card) },
          "frontier" => report.frontier.map { |card| card_ref(card) },
        }
      end
    end

    def blocker_ref(blocker)
      {
        "card" => card_ref(blocker.card),
        "branch" => blocker.branch,
        "pullRequest" => blocker.handoff&.pr_url,
        "pullRequestState" => blocker.pr&.state,
      }
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

    def pending_criteria(data) = data.fetch("criteria").join("\n")
    def branch_name(data) = data.fetch("branch")

    def card_detail(detail)
      lines = [
        "#{detail.fetch("name")} (#{detail.fetch("url")})",
        "List: #{detail.fetch("listName")}",
        "Labels: #{Array(detail["labels"]).map { |label| label["name"] }.join(", ").then { |names| names.empty? ? "none" : names }}",
      ]
      description = detail["description"]
      lines.concat([ "", "Description:", description ]) if description && !description.empty?
      members = Array(detail["members"])
      lines.concat([ "", "Members:", *members.map { |member| "- #{member}" } ]) unless members.empty?
      task_lists = Array(detail["taskLists"])
      unless task_lists.empty?
        lines.concat([ "", "Tasks:" ])
        task_lists.each do |list|
          lines << "#{list["name"]}:"
          lines.concat(Array(list["tasks"]).map { |task| "  [#{task["isCompleted"] ? "x" : " "}] #{task["name"]}" })
        end
      end
      blockers = Array(detail["blockers"])
      unless blockers.empty?
        lines.concat([ "", "Blockers:", *blockers.map { |blocker| "- #{blocker["cardId"]} (#{blocker["completed"] ? "closed" : "open"})" } ])
      end
      comments = Array(detail["comments"])
      unless comments.empty?
        lines.concat([ "", "Comments:", *comments.map { |comment| "- #{comment["text"]}" } ])
      end
      lines.join("\n")
    end

    def board_snapshot(snapshot)
      lines = [ "Board #{snapshot.fetch("boardId")}" ]
      lists = Array(snapshot["lists"])
      cards = Array(snapshot["cards"])
      if lists.empty? && snapshot["listId"]
        lines << "List #{snapshot.fetch("listId")}:"
        lines.concat(cards.map { |card| "  - #{card["name"]} (#{card["url"]})" })
      else
        lists.each do |list|
          lines << "#{list["name"]} (#{list["type"]}):"
          in_list = cards.select { |card| card["listId"] == list["id"] }
          lines.concat(in_list.empty? ? [ "  none" ] : in_list.map { |card| "  - #{card["name"]} (#{card["url"]})" })
        end
      end
      lines.join("\n")
    end

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
