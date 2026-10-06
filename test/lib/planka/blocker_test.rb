require_relative "planka_test_helper"

class Planka::BlockerTest < Minitest::Test
  Card = Struct.new(:name) do
    def to_s = "#{name} (https://planka.example/cards/1)"
  end

  def blocker(name, branch: nil, state: nil, head: branch)
    handoff = Planka::Workflow::Handoff.new(branch:, pr_url: state && "https://github.com/x/y/pull/#{name}") if branch
    pr = Planka::Workflow::PullRequest.new(state:, head:) if state
    Planka::Workflow::Blocker.new(card: Card.new(name), handoff:, pr:)
  end

  def parent(*blockers) = Planka::Workflow::Blocker.parent_branch(blockers)

  def test_no_blockers_stack_on_main
    assert_equal "main", parent
  end

  def test_merged_blockers_stack_on_main
    assert_equal "main", parent(blocker("1", branch: "plan-3/01", state: "MERGED"))
  end

  def test_one_open_blocker_stacks_on_its_branch
    assert_equal "plan-3/05", parent(blocker("4", branch: "plan-3/04", state: "MERGED"), blocker("5", branch: "plan-3/05", state: "OPEN"))
  end

  def test_the_pr_head_wins_over_the_recorded_branch
    assert_equal "plan-3/05-renamed", parent(blocker("5", branch: "plan-3/05", state: "OPEN", head: "plan-3/05-renamed"))
  end

  def test_a_blocker_without_a_pr_counts_as_unmerged
    assert_equal "plan-3/05", parent(blocker("5", branch: "plan-3/05"))
  end

  def test_two_open_blockers_are_ambiguous
    result = parent(blocker("5", branch: "plan-3/05", state: "OPEN"), blocker("6", branch: "plan-3/06", state: "OPEN"))

    assert_equal "AMBIGUOUS: unmerged blockers plan-3/05, plan-3/06", result
  end

  def test_a_blocker_without_a_handoff_comment_is_ambiguous
    assert_equal "AMBIGUOUS: no Branch: comment on 5", parent(blocker("5"))
  end

  def test_describes_itself_for_the_report
    assert_equal "- 5 (https://planka.example/cards/1): branch plan-3/05, PR https://github.com/x/y/pull/5 (open)",
                 blocker("5", branch: "plan-3/05", state: "OPEN").to_s
    assert_equal "- 5 (https://planka.example/cards/1): no Branch: comment", blocker("5").to_s
  end
end
