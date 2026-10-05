require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Cards
        ROOT_HELP = "  describe card CARD  Read card details and related data (read-only)\n".freeze
        GROUP_HELP = "  card CARD  Read card details and related data (read-only)\n".freeze
        HELP = <<~HELP
          usage: planka describe card CARD [--output human|json]
          Read-only: card ID or same-instance card URL; no board setting required.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
          Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
          Example: planka describe card 123 -o json
        HELP

        def self.format(detail)
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

        COMMANDS = {
          ["describe", "card"] => Command.new(aliases: [["describe", "cards"]], resource: "card", collection: "cards", help: HELP, reader: Planka::Cards::Detail, formatter: method(:format)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
