require "json"
require "minitest/autorun"

ENV["PLANKA_BASE_URL"] = "https://planka.home.yountlabs.com"
ENV["PLANKA_BRANCH_PREFIX"] = "lucenta-"
require_relative "../../../lib/planka"
require_relative "../../../lib/planka/workflow"

# The fixture is the markdocs board as Plan 3 was published: a spec card and
# nine ticket cards in ready-for-agent, each blocked on its predecessor(s).
# Helpers edit a fresh copy of it into the state a test needs.
module PlankaTestHelper
  FIXTURE = File.expand_path("../../fixtures/files/planka/board.json", __dir__)

  def payload
    @payload ||= JSON.parse(File.read(FIXTURE)).fetch("included")
  end

  def board
    Planka::Workflow::Board.new(Planka::Board.new(payload))
  end

  def card_id(name_prefix)
    payload["cards"].find { |c| c["name"].start_with?(name_prefix) }.fetch("id")
  end

  def ticket_ids
    labelled = payload["cardLabels"].map { |cl| cl["cardId"] }
    with_criteria = payload["taskLists"].select { |tl| tl["name"] == "Acceptance criteria" }.map { |tl| tl["cardId"] }
    payload["cards"].select { |c| labelled.include?(c["id"]) && with_criteria.include?(c["id"]) }
      .sort_by { |c| c["createdAt"] }.map { |c| c["id"] }
  end

  # Moves the cards to done, completing the tasks linked to them as Planka does.
  def close(*ids)
    done = payload["lists"].find { |l| l["name"] == "done" }.fetch("id")
    payload["cards"].each { |c| c["listId"] = done if ids.include?(c["id"]) }
    payload["tasks"].each { |t| t["isCompleted"] = true if ids.include?(t["linkedCardId"]) }
  end

  def claim(id)
    payload["cardMemberships"] << { "cardId" => id, "userId" => "1" }
  end

  def add_label(name, *ids)
    label = payload["labels"].find { |l| l["name"] == name } ||
      { "id" => "label-#{name}", "name" => name }.tap { |l| payload["labels"] << l }
    ids.each { |id| payload["cardLabels"] << { "id" => "cl-#{name}-#{id}", "cardId" => id, "labelId" => label["id"] } }
  end

  def move(id, list_name)
    list = payload["lists"].find { |l| l["name"] == list_name }.fetch("id")
    payload["cards"].find { |c| c["id"] == id }["listId"] = list
  end
end
