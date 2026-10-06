require "planka/workflow"

module Planka
  module Workflow
    # Human text for workflow results; no IO or session ownership.
    module Format
      module_function

      def ticket_result(result)
        "#{created_ticket(result.fetch("card"))}\nAcceptance criteria: #{Array(result["tasks"]).size}"
      end

      def pending_criteria(data) = data.fetch("criteria").join("\n")
      def guide(data) = data.fetch("instructions")
      def next_selection(data) = data.to_s
      def branch_name(data) = data.fetch("branch")

      def claim(data)
        card = data.fetch("card")
        ["claimed: #{card.fetch("name")} (#{card.fetch("url")})",
         "member added: #{data.fetch("memberAdded")}", "moved: #{data.fetch("moved")}"].join("\n")
      end

      def loop_lock(result)
        return "free" unless result.fetch("held")

        card = result.fetch("card")
        ["held: #{card.fetch("name")} (#{card.fetch("url")})", "claimed: #{result.fetch("claimedAt")}",
         "age: #{result.fetch("ageSeconds")}"].join("\n")
      end

      def spec_sweep(result)
        moved = result.fetch("moved")
        moved.empty? ? "No finished specs" : moved.map { |card| "done: #{card.fetch("name")} (#{card.fetch("url")})" }.join("\n")
      end

      def created_ticket(card)
        name = card["name"] || card["id"]
        details = [card["url"], ("ID: #{card["id"]}" if card["id"] && name != card["id"])].compact
        "Created ticket: #{name}#{details.empty? ? "" : " (#{details.join(", ")})"}"
      end
    end
  end
end
