require_relative "planka_test_helper"

class Planka::HandoffTest < Minitest::Test
  def test_parses_plain_lines
    handoff = Planka::Handoff.parse("Branch: plan-3/01-contract-edits\nPR: https://github.com/marshally/markdocs/pull/8")

    assert_equal "plan-3/01-contract-edits", handoff.branch
    assert_equal "https://github.com/marshally/markdocs/pull/8", handoff.pr_url
  end

  def test_parses_markdown_decoration
    handoff = Planka::Handoff.parse("Branch: `plan-3/01-contract-edits`\nPR: <https://github.com/marshally/markdocs/pull/8>.")

    assert_equal "plan-3/01-contract-edits", handoff.branch
    assert_equal "https://github.com/marshally/markdocs/pull/8", handoff.pr_url
  end

  def test_finds_the_lines_among_other_text
    handoff = Planka::Handoff.parse("Opened the PR.\n\nBranch: plan-3/02-create\nPR: https://github.com/x/y/pull/9\n\nAll criteria ticked.")

    assert_equal "plan-3/02-create", handoff.branch
  end

  def test_a_branch_without_a_pr_line
    assert_nil Planka::Handoff.parse("Branch: plan-3/02-create").pr_url
  end

  def test_text_without_a_branch_line_is_not_a_handoff
    assert_nil Planka::Handoff.parse("Claimed; starting on the migration.")
  end

  def test_latest_takes_the_newest_handoff_comment
    comments = [
      { "createdAt" => "2026-09-24T10:00:00Z", "text" => "Branch: old\nPR: https://github.com/x/y/pull/1" },
      { "createdAt" => "2026-09-25T10:00:00Z", "text" => "Branch: new\nPR: https://github.com/x/y/pull/2" },
      { "createdAt" => "2026-09-26T10:00:00Z", "text" => "Moved to done." }
    ]

    assert_equal "new", Planka::Handoff.latest(comments).branch
  end

  def test_latest_is_nil_without_a_handoff_comment
    assert_nil Planka::Handoff.latest([ { "createdAt" => "2026-09-24T10:00:00Z", "text" => "Claimed." } ])
  end
end
