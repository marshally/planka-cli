require_relative "planka_test_helper"

class Planka::NextCardTest < Minitest::Test
  include PlankaTestHelper

  Comments = Struct.new(:by_card) do
    def comments(card_id) = by_card.fetch(card_id, [])
  end

  PullRequests = Struct.new(:by_url) do
    def find(url) = by_url[url]
  end

  def next_card(label, comments: {}, prs: {})
    Planka::Workflow::NextCard.for(label, board:, comments: Comments.new(comments), pull_requests: PullRequests.new(prs)).to_s
  end

  def handoff(branch, pr) = [ { "createdAt" => "2026-09-24T10:00:00Z", "text" => "Branch: #{branch}\nPR: #{pr}" } ]

  def pr(state, head) = Planka::Workflow::PullRequest.new(state:, head:)

  def line(prefix) = board.card(card_id(prefix)).to_s

  def test_a_fresh_feature_picks_the_first_ticket_on_main
    assert_equal <<~REPORT.chomp, next_card("feature:workspaces")
      card: #{line("Contract edits")}
      spec: #{line("Spec:")}
      nn: 01
      blockers: none
      parent: main
    REPORT
  end

  def test_a_quarantined_ticket_is_never_picked_and_waits_as_quarantined
    add_label("quarantine", card_id("Contract edits"))

    report = next_card("feature:workspaces")

    assert report.start_with?("none:\n"), report
    assert_includes report.lines.map(&:chomp), "- #{line("Contract edits")}: quarantined"
  end

  def test_an_open_blocker_pr_stacks_on_its_branch
    close(card_id("Contract edits"))
    report = next_card("feature:workspaces",
      comments: { card_id("Contract edits") => handoff("plan-3/01-contract-edits", "https://github.com/x/y/pull/8") },
      prs: { "https://github.com/x/y/pull/8" => pr("OPEN", "plan-3/01-contract-edits") })

    assert_equal <<~REPORT.chomp, report
      card: #{line("Create a workspace")}
      spec: #{line("Spec:")}
      nn: 02
      blockers:
      - #{line("Contract edits")}: branch plan-3/01-contract-edits, PR https://github.com/x/y/pull/8 (open)
      parent: plan-3/01-contract-edits
    REPORT
  end

  def test_a_merged_blocker_pr_stacks_on_main
    close(card_id("Contract edits"))
    report = next_card("feature:workspaces",
      comments: { card_id("Contract edits") => handoff("plan-3/01-contract-edits", "https://github.com/x/y/pull/8") },
      prs: { "https://github.com/x/y/pull/8" => pr("MERGED", "plan-3/01-contract-edits") })

    assert_equal "parent: main", report.lines.last
  end

  def test_a_blocker_without_a_handoff_comment_is_ambiguous
    close(card_id("Contract edits"))

    assert_match(/^parent: AMBIGUOUS: no Branch: comment on Contract edits/, next_card("feature:workspaces"))
  end

  def test_ticket_order_follows_creation_not_position
    close(*ticket_ids.first(5))
    report = next_card("feature:workspaces",
      comments: { card_id("Documents inside") => handoff("plan-3/05-documents", "https://github.com/x/y/pull/12") },
      prs: { "https://github.com/x/y/pull/12" => pr("OPEN", "plan-3/05-documents") })

    assert_match(/^card: Adding members/, report)
    assert_match(/^nn: 06$/, report)
    assert_equal "parent: plan-3/05-documents", report.lines.last
  end

  def test_nothing_takeable_lists_what_holds_each_waiting_ticket
    claim(card_id("Contract edits"))
    report = next_card("feature:workspaces").lines(chomp: true)

    assert_equal "none:", report[0]
    assert_equal "- #{line("Contract edits")}: claimed", report[1]
    assert_equal "- #{line("Create a workspace")}: blocked by #{board.card(card_id("Contract edits")).name}", report[2]
    assert_equal 10, report.size
  end

  def position(id, value) = payload["cards"].find { |c| c["id"] == id }["position"] = value

  def unblock_all = payload["tasks"].each { |task| task["isCompleted"] = true }

  def test_no_label_picks_the_top_takeable_ticket_and_never_a_spec
    unblock_all
    position(card_id("Spec:"), 1)
    position(card_id("Adding members"), 2)

    assert_equal <<~REPORT.chomp, next_card(nil)
      card: #{line("Adding members")}
      spec: #{line("Spec:")}
      blockers:
      - #{line("Documents inside")}: no Branch: comment
      parent: AMBIGUOUS: no Branch: comment on #{board.card(card_id("Documents inside")).name}
    REPORT
  end

  def test_no_label_skips_claimed_and_blocked_cards_above
    unblock_all
    claim(card_id("Contract edits"))
    position(card_id("Contract edits"), 1)
    payload["tasks"].each { |task| task["isCompleted"] = false if task["linkedCardId"] == card_id("Contract edits") }
    position(card_id("Create a workspace"), 2)
    position(card_id("Adding members"), 3)

    assert_equal "card: #{line("Adding members")}", next_card(nil).lines(chomp: true).first
  end

  def test_no_label_on_a_ticket_without_a_feature_prints_no_spec
    payload["cardLabels"].clear
    assert_equal <<~REPORT.chomp, next_card(nil)
      card: #{line("Contract edits")}
      spec: none
      blockers: none
      parent: main
    REPORT
  end

  def test_no_label_with_nothing_takeable_lists_the_ready_tickets
    claim(card_id("Contract edits"))
    report = next_card(nil).lines(chomp: true)

    assert_equal "none:", report[0]
    assert_includes report, "- #{line("Contract edits")}: claimed"
    assert_equal 10, report.size
  end

  def test_an_effort_label_prints_the_frontier_in_position_order
    map, *children = [ card_id("Spec:"), *ticket_ids.first(4) ]
    add_label("effort:search", map, *children)
    add_label("wayfinder:map", map)
    move(map, "in-progress")
    payload["tasks"].each { |task| task["isCompleted"] = true }
    claim(card_id("Create a workspace"))

    assert_equal <<~REPORT.chomp, next_card("effort:search")
      card: #{line("Lookup cop")}
      map: #{line("Spec:")}
      frontier:
      - #{line("Lookup cop")}
      - #{line("Open a workspace")}
      - #{line("Contract edits")}
    REPORT
  end

  def test_an_empty_frontier
    add_label("effort:search", card_id("Spec:"))
    add_label("wayfinder:map", card_id("Spec:"))

    assert_equal "card: none\nmap: #{line("Spec:")}\nfrontier: none", next_card("effort:search")
  end
end
