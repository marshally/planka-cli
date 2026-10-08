require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_comments"

class CommentResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  CARD = FakePlanka::PARENT_CARD
  BOARD = FakePlanka::BOARD_ID
  COMMENT = "500000000000000001"

  def setup = @server = FakeComments.new
  def teardown = @server.stop

  def planka(*args, env: {}, direct: nil)
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "fixture", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{direct || "planka"}", *args, chdir: Dir.tmpdir)
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status.exitstatus]
  end

  def test_collection_reads_concise_comments_without_resource_writes
    @server.comments.first["privateField"] = "excluded"
    doc, err, status = json("get", "comments", "--card", CARD)
    assert_equal 0, status, err
    assert_equal({ "data" => [{ "id" => COMMENT, "cardId" => CARD, "userId" => "123", "text" => "Parent context note.", "createdAt" => "2026-09-01T00:00:00.000Z", "updatedAt" => nil }], "meta" => { "complete" => true }, "error" => nil }, doc)
    assert_equal ["POST", "GET", "GET", "DELETE"], @server.requests.map(&:first)
    assert_equal 1, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_collection_follows_native_pages_and_reports_exact_limit_completeness
    original = @server.comments.first
    51.times { |index| @server.comments << original.merge("id" => (600_000_000_000_000_000 + index).to_s, "text" => "Note #{index}") }
    doc, err, status = json("get", "comment", "--card", CARD)
    assert_equal 0, status, err
    assert_equal 52, doc["data"].size
    assert_equal "600000000000000050", doc.dig("data", 0, "id")
    assert_equal COMMENT, doc["data"].last["id"]
    assert_equal true, doc.dig("meta", "complete")
    assert_includes @server.requests.map { |_, path, _| path }, "/api/cards/#{CARD}/comments?beforeId=600000000000000001"
    [1, 50, 52].each do |limit|
      doc, _, status = json("get", "comments", "--card", CARD, "--limit", limit.to_s)
      assert_equal 0, status
      assert_equal limit, doc["data"].size
      assert_equal limit == 52, doc.dig("meta", "complete")
    end
    out, err, status = planka("get", "comments", "--card", CARD, "--limit", "1")
    assert status.success?, err
    assert_includes out, "Results truncated"
  end

  def test_malformed_pages_preserve_only_verified_comments_and_do_not_loop
    valid = @server.comments.first.dup
    invalid = [valid.merge("cardId" => "999"), valid, valid.merge("id" => "600000000000000000"),
               valid.merge("id" => "400", "text" => 42), valid.merge("id" => "400", "userId" => "bad"), nil]
    invalid.each do |record|
      @server.inject("GET", %r{/comments}, { "items" => [valid, record] })
      doc, err, status = json("get", "comments", "--card", CARD)
      assert_equal 1, status, err
      assert_equal([COMMENT], doc["data"].map { |comment| comment["id"] })
      assert_equal false, doc.dig("meta", "complete")
      assert_equal "api_error", doc.dig("error", "code")
    end
    assert_equal invalid.size, @server.counts("GET", %r{/comments})
    assert_equal invalid.size, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_individual_reads_one_comment_with_explicit_card_scope
    doc, err, status = json("get", "comment", COMMENT, "--card", "#{@server.base_url}/cards/#{CARD}", env: { "PLANKA_BOARD_ID" => "999" })
    assert_equal 0, status, err
    assert_equal COMMENT, doc.dig("data", "id")
    assert_equal({}, doc["meta"])
    assert_nil doc["error"]
    out, err, status = planka("get", "comments", COMMENT, "--card", "Spec: Work-next refinement", "--board", BOARD)
    assert status.success?, err
    assert_includes out, "Comment #{COMMENT} on card #{CARD}"
    assert_includes out, "Parent context note."
    doc, _, status = json("get", "comment", "999", "--card", CARD)
    assert_equal 1, status
    assert_equal "not_found", doc.dig("error", "code")
    assert_nil doc["data"]
  end

  def test_create_posts_exact_multiline_unicode_once_and_returns_retrievable_identity
    text = "  Café 😀\nBranch: topic\n最後の行\n"
    doc, err, status = json("create", "comments", "--card", CARD, "--text", text)
    assert_equal 0, status, err
    assert_equal true, doc.dig("meta", "changed")
    created = doc["data"]
    refute_equal COMMENT, created["id"]
    assert_equal CARD, created["cardId"]
    assert_equal text, created["text"]
    read, err, status = json("get", "comment", created["id"], "--card", CARD)
    assert_equal 0, status, err
    assert_equal created, read["data"]
    writes = @server.requests.select { |method, path, _| method == "POST" && !path.include?("access-tokens") }
    assert_equal([["POST", "/api/cards/#{CARD}/comments", { "text" => text }]], writes.map { |method, path, body| [method, path, JSON.parse(body)] })
  end

  def test_update_changes_only_text_and_identical_text_is_a_noop
    doc, err, status = json("update", "comments", COMMENT, "--card", CARD, "--text", "New\n내용 😀")
    assert_equal 0, status, err
    assert_equal true, doc.dig("meta", "changed")
    assert_equal COMMENT, doc.dig("data", "id")
    assert_equal "123", doc.dig("data", "userId")
    assert_equal "2026-09-01T00:00:00.000Z", doc.dig("data", "createdAt")
    read, _, status = json("get", "comment", COMMENT, "--card", CARD)
    assert_equal 0, status
    assert_equal "New\n내용 😀", read.dig("data", "text")
    doc, _, status = json("update", "comment", COMMENT, "--card", CARD, "--text", "New\n내용 😀")
    assert_equal 0, status
    assert_equal false, doc.dig("meta", "changed")
    writes = @server.requests.select { |method, _, _| method == "PATCH" }
    assert_equal 1, writes.size
    assert_equal "/api/comments/#{COMMENT}", writes.first[1]
    assert_equal({ "text" => "New\n내용 😀" }, JSON.parse(writes.first.last))
  end

  def test_delete_only_the_target_comment_preserves_card_and_other_comments
    @server.comments << @server.comments.first.merge("id" => "600", "text" => "Retained")
    doc, err, status = json("delete", "comments", COMMENT, "--card", CARD)
    assert_equal 0, status, err
    assert_equal true, doc.dig("meta", "changed")
    assert_equal true, doc.dig("data", "deleted")
    assert_equal COMMENT, doc.dig("data", "id")
    read, _, status = json("get", "comments", "--card", CARD)
    assert_equal 0, status
    assert_equal(["600"], read["data"].map { |comment| comment["id"] })
    card, _, status = json("get", "card", CARD)
    assert_equal 0, status
    assert_equal CARD, card.dig("data", "id")
    deletes = @server.requests.select { |method, path, _| method == "DELETE" && !path.include?("access-tokens") }
    assert_equal [["DELETE", "/api/comments/#{COMMENT}", ""]], deletes
  end

  def test_malformed_creation_retains_returned_identity_for_reconciliation
    @server.inject("POST", %r{/comments$}, { "item" => { "id" => "987", "cardId" => CARD, "text" => nil } })
    doc, err, status = json("create", "comment", "--card", CARD, "--text", "new")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_equal "987", doc.dig("data", "id")
    assert_nil doc.dig("data", "text")
    assert_equal({ "action" => "readback-comment", "resources" => [{ "type" => "card", "id" => CARD }, { "type" => "comment", "id" => "987" }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/comments$})
  end

  def test_unknown_create_is_not_retried_and_can_be_reconciled_by_reading_the_card
    @server.inject("POST", %r{/comments$}, :apply_then_drop)
    doc, err, status = json("create", "comment", "--card", CARD, "--text", "Written once")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "id")
    assert_equal CARD, doc.dig("data", "cardId")
    assert_equal "readback-comments", doc.dig("error", "recovery", "action")
    read, _, status = json("get", "comments", "--card", CARD)
    assert_equal 0, status
    assert_equal(1, read["data"].count { |comment| comment["text"] == "Written once" })
    assert_equal 1, @server.counts("POST", %r{/comments$})
    assert_equal 2, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_unknown_updates_and_deletions_preserve_identity_and_reconcile_without_retries
    [["update", "PATCH", ["--text", "Changed"], "text"], ["delete", "DELETE", [], "deleted"]].each do |verb, method, arguments, uncertain_field|
      @server.inject(method, %r{/api/comments/}, :apply_then_drop)
      doc, err, status = json(verb, "comment", COMMENT, "--card", CARD, *arguments)
      assert_equal 1, status, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_nil doc.dig("data", uncertain_field)
      assert_equal COMMENT, doc.dig("data", "id")
      assert_equal "123", doc.dig("data", "userId")
      assert_equal "readback-comment", doc.dig("error", "recovery", "action")
      assert_equal 1, @server.counts(method, %r{/api/comments/})
      read, _, status = json("get", "comments", "--card", CARD)
      assert_equal 0, status
      verb == "update" ? assert_equal("Changed", read.dig("data", 0, "text")) : assert_empty(read["data"])
    end
  end

  def test_rejected_writes_preserve_known_state_and_the_primary_error_despite_cleanup_failure
    [["create", "POST", [], 403], ["update", "PATCH", [COMMENT], 404], ["delete", "DELETE", [COMMENT], 403]].each do |verb, method, references, status_code|
      @server.inject(method, %r{/comments(?:/|$)}, status_code)
      @server.inject("DELETE", %r{access-tokens/me$}, 403)
      text = verb == "delete" ? [] : ["--text", "New"]
      doc, err, status = json(verb, "comment", *references, "--card", CARD, *text)
      assert_equal 1, status
      assert_equal status_code == 404 ? "not_found" : "authorization_error", doc.dig("error", "code")
      assert_equal false, doc.dig("meta", "changed")
      verb == "create" ? assert_nil(doc.dig("data", "id")) : assert_equal(COMMENT, doc.dig("data", "id"))
      refute doc["data"].key?("deleted")
      assert_includes err, "session cleanup failed"
      refute_includes doc.to_json, "private upstream body"
    end
    doc, _, status = json("get", "comment", COMMENT, "--card", CARD)
    assert_equal 0, status
    assert_equal "Parent context note.", doc.dig("data", "text")
  end

  def test_later_page_failure_preserves_limited_results_and_exact_page_boundary_needs_readback
    original = @server.comments.first
    @server.comments.clear
    50.times { |index| @server.comments << original.merge("id" => (100 + index).to_s) }
    @server.inject("GET", /beforeId=100$/, 500)
    doc, err, status = json("get", "comments", "--card", CARD, "--limit", "1")
    assert_equal 1, status, err
    assert_equal(["149"], doc["data"].map { |comment| comment["id"] })
    assert_equal false, doc.dig("meta", "complete")
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal 1, @server.counts("GET", /beforeId=100$/)
    doc, err, status = json("get", "comments", "--card", CARD, "--limit", "50")
    assert_equal 0, status, err
    assert_equal 50, doc["data"].size
    assert_equal true, doc.dig("meta", "complete")
    assert_equal 2, @server.counts("GET", /beforeId=100$/)
  end

  def test_invalid_inputs_fail_before_any_request
    commands = [
      ["get", "comments"], ["get", "comment", COMMENT],
      ["get", "comment", COMMENT, "--card", CARD, "--limit", "1"],
      ["get", "comments", "--card", CARD, "--limit", "0"],
      ["get", "comments", "--card", CARD, "--name", "note"],
      ["get", "comments", "--card", CARD, "--label", "1"],
      ["get", "comments", "--card", CARD, "--member", "1"],
      ["get", "comments", "--card", CARD, "--card", "999"],
      ["get", "comment", "note", "--card", CARD],
      ["get", "comment", "#{@server.base_url}/comments/#{COMMENT}", "--card", CARD],
      ["get", "comments", "--card", "https://other.example/cards/1"],
      ["get", "comments", "--card", "#{@server.base_url}/cards/1?secret=bad"],
      ["create", "comment", "--card", CARD], ["create", "comment", "--text", "new"],
      ["create", "comment", "--card", CARD, "--text", ""],
      ["update", "comment", COMMENT, "--card", CARD],
      ["update", "comment", COMMENT, "--card", CARD, "--text", " \n\t"],
      ["update", "comment", COMMENT, "--card", CARD, "--text", "one", "--text", "two"],
      ["delete", "comment", "--card", CARD],
      ["delete", "comment", COMMENT, "--card", CARD, "--cascade"]
    ]
    commands.each do |arguments|
      doc, err, status = json(*arguments)
      assert_equal 2, status, "#{arguments.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code")
    end
    assert_empty @server.requests
  end

  def test_scope_assertions_and_ambiguous_card_names_fail_without_resource_writes
    doc, _, status = json("delete", "comment", COMMENT, "--card", CARD, "--board", "999")
    assert_equal 2, status
    assert_equal "invalid_input", doc.dig("error", "code")
    @server.add_card("Spec: Work-next refinement", FakePlanka::LIST_READY)
    doc, _, status = json("get", "comments", "--card", "Spec: Work-next refinement", "--board", BOARD)
    assert_equal 2, status
    assert_match(/candidate IDs: #{CARD}, /, doc.dig("error", "message"))
    other = @server.cards.last["id"]
    doc, _, status = json("update", "comment", COMMENT, "--card", other, "--text", "Unapplied")
    assert_equal 1, status
    assert_equal "not_found", doc.dig("error", "code")
    assert_equal false, doc.dig("meta", "changed")
    assert_equal 0, @server.counts("PATCH", %r{/comments/})
    assert_equal 0, @server.counts("DELETE", %r{/api/comments/})
  end

  def test_all_commands_require_connection_settings_before_requests
    commands = [["get", "comments"], ["get", "comment", COMMENT], ["create", "comment", "--text", "new"],
                ["update", "comment", COMMENT, "--text", "new"], ["delete", "comment", COMMENT]]
    %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].each do |setting|
      commands.each do |arguments|
        doc, _, status = json(*arguments, "--card", CARD, env: { setting => nil })
        assert_equal 1, status
        assert_equal "configuration_error", doc.dig("error", "code")
      end
    end
    doc, _, status = json("get", "comments", "--card", "Spec: Work-next refinement", env: { "PLANKA_BOARD_ID" => "invalid" })
    assert_equal 1, status
    assert_equal "configuration_error", doc.dig("error", "code")
    assert_empty @server.requests
  end

  def test_offline_help_lists_all_comment_commands_and_aliases
    empty = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    %w[get create update delete].each do |verb|
      %w[comment comments].each do |resource|
        out, err, status = planka(verb, resource, "--help", env: empty)
        assert status.success?, err
        assert_includes out, "usage: planka #{verb} comment"
        assert_includes out, "--card"
      end
      out, err, status = planka(verb, "--help", env: empty)
      assert status.success?, err
      assert_match(/^  comments? /, out)
    end
    out, err, status = planka("--help", env: empty)
    assert status.success?, err
    assert_includes out, "create comment"
    assert_includes out, "update comment"
    assert_includes out, "delete comment"
    assert_empty @server.requests
  end

  def test_legacy_comment_preserves_text_bare_json_human_output_and_exits
    [nil, "planka-comment"].each do |direct|
      arguments = direct ? [] : ["comment"]
      text = "Branch: topic\nPR: https://github.com/example/repo/pull/1\nCafé 😀"
      out, err, status = planka(*arguments, CARD, text, "--output", "json", direct: direct)
      assert status.success?, err
      assert_empty err
      doc = JSON.parse(out)
      assert_equal %w[cardId comment], doc.keys.sort
      assert_equal CARD, doc["cardId"]
      assert_equal %w[createdAt id text userId], doc["comment"].keys.sort
      assert_equal text, doc.dig("comment", "text")
      out, err, status = planka(*arguments, CARD, text, direct: direct)
      assert status.success?, err
      assert_equal "Commented on card #{CARD}\n", out
      assert_empty err
      _, _, status = planka(*arguments, direct: direct)
      assert_equal 1, status.exitstatus
      out, err, status = planka(*arguments, "--help", direct: direct)
      assert status.success?, err
      assert_includes out, "planka create comment --card CARD --text TEXT"
    end
  end

  def test_malformed_write_responses_never_claim_success_or_overwrite_the_target_identity
    [["update", "PATCH", ["--text", "new"]], ["delete", "DELETE", []]].each do |verb, method, arguments|
      @server.inject(method, %r{/api/comments/}, { "item" => @server.comments.first.merge("id" => "999") })
      doc, err, status = json(verb, "comment", COMMENT, "--card", CARD, *arguments)
      assert_equal 1, status, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_equal COMMENT, doc.dig("data", "id")
      assert_equal 1, @server.counts(method, %r{/api/comments/})
    end
    @server.inject("POST", %r{/comments$}, { "item" => { "id" => "999", "cardId" => "777", "text" => "new" } })
    doc, _, status = json("create", "comment", "--card", CARD, "--text", "new")
    assert_equal 1, status
    assert_nil doc.dig("data", "id")
    assert_equal CARD, doc.dig("data", "cardId")
    assert_equal "readback-comments", doc.dig("error", "recovery", "action")
  end

  def test_successful_read_and_write_survive_cleanup_failure_and_nullable_authors
    @server.comments.first["userId"] = nil
    @server.comments.first["createdAt"] = nil
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    doc, err, status = json("get", "comment", COMMENT, "--card", CARD)
    assert_equal 0, status
    assert_nil doc.dig("data", "userId")
    assert_nil doc.dig("data", "createdAt")
    assert_nil doc["error"]
    assert_includes err, "session cleanup failed"
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    doc, err, status = json("create", "comment", "--card", CARD, "--text", "new")
    assert_equal 0, status
    assert_equal true, doc.dig("meta", "changed")
    assert_nil doc["error"]
    assert_includes err, "session cleanup failed"
  end

  def test_invalid_page_documents_and_repeated_boundary_fail_safely
    [nil, {}, [nil]].each do |items|
      @server.inject("GET", %r{/comments}, { "items" => items })
      doc, err, status = json("get", "comments", "--card", CARD)
      assert_equal 1, status, err
      assert_equal [], doc["data"]
      assert_equal false, doc.dig("meta", "complete")
      assert_equal "api_error", doc.dig("error", "code")
    end
    record = @server.comments.first
    page = 50.times.map { |index| record.merge("id" => (1000 - index).to_s) }
    @server.inject("GET", %r{/comments$}, { "items" => page })
    @server.inject("GET", /beforeId=951$/, { "items" => [page.last] })
    doc, _, status = json("get", "comments", "--card", CARD)
    assert_equal 1, status
    assert_equal 50, doc["data"].size
    assert_equal false, doc.dig("meta", "complete")
    assert_equal 1, @server.counts("GET", /beforeId=951$/)
  end

  def test_native_text_limit_counts_utf16_units_before_requests
    # Construct the public CLI arguments in the subprocess to avoid the OS argv
    # size cap, which is smaller than Planka's native text limit.
    script = 'ARGV.concat(["--text", "😀" * 524_289]); load ARGV.shift'
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "fixture" }
    out, err, status = Open3.capture3(settings, RbConfig.ruby, "-I#{ROOT}/lib", "-e", script, "#{ROOT}/exe/planka",
                                      "create", "comment", "--card", CARD, "-o", "json", chdir: Dir.tmpdir)
    assert_equal 2, status.exitstatus, err
    doc = JSON.parse(out)
    assert_equal "invalid_input", doc.dig("error", "code")
    assert_includes doc.dig("error", "message"), "1048576 UTF-16 units"
    assert_empty @server.requests
  end
end
