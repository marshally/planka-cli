require "planka/workflow"

module Planka
  module Workflow
    # Human text and legacy workflow result projections; no IO or session ownership.
    module Format
      module_function

      def ticket_result(result)
        "#{created_ticket(result.fetch("card"))}\nAcceptance criteria: #{Array(result["tasks"]).size}"
      end

      def card_ref(card) = { "id" => card.id, "name" => card.name, "url" => card.url }

      def next_card(report)
        case report
        when NextCard::Pick
          {
            "card" => card_ref(report.card),
            "specs" => report.spec.map { |card| card_ref(card) },
            "number" => report.nn,
            "blockers" => report.blockers.map { |blocker| blocker_ref(blocker) },
            "parent" => Blocker.parent_branch(report.blockers),
          }
        when NextCard::Waiting
          {
            "card" => nil,
            "waiting" => report.cards.map do |card|
              card_ref(card).merge("claimed" => card.claimed?, "blockedBy" => card.open_blockers.map { |blocker| card_ref(blocker) })
            end,
          }
        when NextCard::FrontierReport
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

      def pending_criteria(data) = data.fetch("criteria").join("\n")
      def branch_name(data) = data.fetch("branch")

      def loop_lock(result)
        return "free" unless result.fetch("held")

        card = result.fetch("card")
        ["held: #{card.fetch('name')} (#{card.fetch('url')})", "claimed: #{result.fetch('claimedAt')}",
          "age: #{result.fetch('ageSeconds')}"].join("\n")
      end

      def spec_sweep(result)
        moved = result.fetch("moved")
        moved.empty? ? "No finished specs" : moved.map { |card| "done: #{card.fetch('name')} (#{card.fetch('url')})" }.join("\n")
      end

      def created_ticket(card)
        name = card["name"] || card["id"]
        details = [card["url"], ("ID: #{card["id"]}" if card["id"] && name != card["id"])].compact
        "Created ticket: #{name}#{details.empty? ? "" : " (#{details.join(', ')})"}"
      end
    end
  end
end
