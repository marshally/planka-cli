require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_planka"

class LabelResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  LABEL = FakePlanka::LABEL_ENHANCEMENT
  BOARD = FakePlanka::BOARD_ID

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, direct: nil)
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com", "PLANKA_AGENT_PASSWORD" => "fixture", "PLANKA_BOARD_ID" => nil }
    Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{direct || "planka"}", *args, chdir: Dir.tmpdir)
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status.exitstatus]
  end

  def test_collection_reads_whitelisted_labels_without_resource_writes
    @server.labels.first["privateField"] = "excluded"
    doc, err, status = json("get", "labels", "--board", BOARD)
    assert_equal 0, status, err
    assert_equal({ "data" => [{ "id" => LABEL, "boardId" => BOARD, "name" => "enhancement", "color" => "berry-red", "position" => 65_536, "createdAt" => nil, "updatedAt" => nil }], "meta" => { "complete" => true }, "error" => nil }, doc)
    assert_equal ["POST", "GET", "DELETE"], @server.requests.map(&:first)
    assert_equal 1, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_collection_orders_by_position_and_id_and_filters_before_limit
    @server.add_label("other")
    @server.add_label("enhancement")
    @server.labels.last["position"] = 1
    early = @server.labels.last.fetch("id")
    doc, err, status = json("get", "label", "--board", BOARD, "--name", "enhancement", "--limit", "1")
    assert_equal 0, status, err
    assert_equal([early], doc.fetch("data").map { |record| record["id"] })
    assert_equal false, doc.dig("meta", "complete")
    doc, _, status = json("get", "labels", "--board", BOARD, "--name", "other", "--limit", "1")
    assert_equal 0, status
    assert_equal true, doc.dig("meta", "complete")
    out, _, status = planka("get", "labels", "--board", BOARD, "--limit", "1")
    assert status.success?
    assert_includes out, "Results truncated"
    doc, _, status = json("get", "labels", "--board", BOARD, "--name", "absent")
    assert_equal 0, status
    assert_equal [], doc["data"]
    assert_equal true, doc.dig("meta", "complete")
  end

  def test_malformed_collection_preserves_only_valid_matching_results
    @server.add_label("other")
    @server.add_label("broken")
    @server.labels.last["position"] = "invalid"
    doc, err, status = json("get", "labels", "--board", BOARD, "--name", "enhancement", "--limit", "1")
    assert_equal 1, status, err
    assert_equal([LABEL], doc.fetch("data").map { |record| record["id"] })
    assert_equal false, doc.dig("meta", "complete")
    assert_equal "api_error", doc.dig("error", "code")
    assert_equal 1, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_individual_scope_references_and_parent_mismatches
    [LABEL, "enhancement", "#{@server.base_url}/labels/#{LABEL}"].each do |reference|
      doc, err, status = json("get", "label", reference, "--board", "#{@server.base_url}/boards/#{BOARD}")
      assert_equal 0, status, err
      assert_equal LABEL, doc.dig("data", "id")
      assert_equal({}, doc["meta"])
    end
    doc, _, status = json("get", "label", LABEL)
    assert_equal 1, status
    assert_equal "configuration_error", doc.dig("error", "code")
    doc, _, status = json("get", "label", LABEL, env: { "PLANKA_BOARD_ID" => "bad" })
    assert_equal 1, status
    assert_equal "configuration_error", doc.dig("error", "code")
    @server.add_label("enhancement")
    doc, _, status = json("get", "label", "enhancement", "--board", BOARD)
    assert_equal 2, status
    assert_match(/candidate IDs: #{LABEL}, /, doc.dig("error", "message"))
    doc, _, status = json("get", "label", "missing", "--board", BOARD)
    assert_equal 1, status
    assert_equal "not_found", doc.dig("error", "code")
    @server.labels.first["boardId"] = "999"
    doc, _, status = json("get", "label", LABEL, "--board", BOARD)
    assert_equal 1, status
    assert_equal "not_found", doc.dig("error", "code")
  end

  def test_create_always_creates_even_when_name_exists_and_defaults_to_append
    doc, err, status = json("create", "labels", "--board", BOARD, "--name", "enhancement", "--color", "lagoon-blue")
    assert_equal 0, status, err
    created = doc.fetch("data")
    refute_equal LABEL, created["id"]
    assert_equal "enhancement", created["name"]
    assert_equal "lagoon-blue", created["color"]
    assert_equal 131_072, created["position"]
    assert_equal true, doc.dig("meta", "changed")
    read, _, status = json("get", "labels", "--board", BOARD)
    assert_equal 0, status
    assert_equal([LABEL, created["id"]], read["data"].map { |record| record["id"] })
    writes = @server.requests.select { |method, path, _| method == "POST" && path.end_with?("/labels") }
    assert_equal 1, writes.size
    assert_equal({ "name" => "enhancement", "color" => "lagoon-blue", "position" => 131_072 }, JSON.parse(writes.first.last))
  end

  def test_unknown_create_requires_readback_without_duplicate_retry
    @server.inject("POST", %r{/labels$}, :apply_then_drop)
    doc, err, status = json("create", "label", "--board", BOARD, "--name", "new", "--color", "berry-red")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "id")
    assert_equal({ "action" => "readback-labels", "resources" => [{ "type" => "board", "id" => BOARD }] }, doc.dig("error", "recovery"))
    assert_equal 1, @server.counts("POST", %r{/labels$})
    read, _, status = json("get", "labels", "--board", BOARD, "--name", "new")
    assert_equal 0, status
    assert_equal 1, read["data"].size
    assert_equal 2, @server.counts("DELETE", %r{access-tokens/me$})
  end

  def test_update_changes_only_supplied_fields_and_identical_updates_are_noops
    doc, err, status = json("update", "labels", "#{@server.base_url}/labels/#{LABEL}", "--board", BOARD, "--name", "renamed")
    assert_equal 0, status, err
    assert_equal true, doc.dig("meta", "changed")
    assert_equal "renamed", doc.dig("data", "name")
    assert_equal "berry-red", doc.dig("data", "color")
    assert_equal 65_536, doc.dig("data", "position")
    request = @server.requests.find { |method, path, _| method == "PATCH" && path.end_with?("/labels/#{LABEL}") }
    assert_equal({ "name" => "renamed" }, JSON.parse(request.last))
    doc, _, status = json("update", "label", LABEL, "--board", BOARD, "--name", "renamed")
    assert_equal 0, status
    assert_equal false, doc.dig("meta", "changed")
    assert_equal 1, @server.counts("PATCH", %r{/labels/})
    doc, _, status = json("update", "label", LABEL, "--board", BOARD, "--color", "lagoon-blue", "--position", "0")
    assert_equal 0, status
    assert_equal "renamed", doc.dig("data", "name")
    assert_equal "lagoon-blue", doc.dig("data", "color")
    assert_equal 0, doc.dig("data", "position")
  end

  def test_delete_removes_only_label_with_native_assignment_cleanup
    @server.add_label("retained")
    retained = @server.labels.last["id"]
    [LABEL, retained].each do |label|
      _, err, status = json("add", "label", label, "--card", FakePlanka::PARENT_CARD)
      assert_equal 0, status, err
    end
    doc, err, status = json("delete", "labels", LABEL, "--board", BOARD)
    assert_equal 0, status, err
    assert_equal LABEL, doc.dig("data", "id")
    assert_equal true, doc.dig("data", "deleted")
    assert_equal true, doc.dig("meta", "changed")
    collection, _, status = json("get", "labels", "--board", BOARD)
    assert_equal 0, status
    assert_equal([retained], collection["data"].map { |record| record["id"] })
    card, err, status = json("describe", "card", FakePlanka::PARENT_CARD)
    assert_equal 0, status, err
    assert_equal FakePlanka::PARENT_CARD, card.dig("data", "id")
    assert_equal(["retained"], card.dig("data", "labels").map { |record| record["name"] })
    deletions = @server.requests.select { |method, path, _| method == "DELETE" && !path.include?("access-tokens") }
    assert_equal [["DELETE", "/api/labels/#{LABEL}", ""]], deletions
  end

  def test_missing_create_item_is_unknown_with_board_recovery
    @server.inject("POST", %r{/labels$}, { "unexpected" => "response" })
    doc, err, status = json("create", "label", "--board", BOARD, "--name", "new", "--color", "berry-red")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "id")
    assert_equal "readback-labels", doc.dig("error", "recovery", "action")
    assert_equal 1, @server.counts("POST", %r{/labels$})
  end

  def test_create_scope_failure_does_not_expose_a_collection_as_mutation_data
    @server.labels.first["position"] = nil
    doc, err, status = json("create", "label", "--board", BOARD, "--name", "new", "--color", "berry-red")
    assert_equal 1, status, err
    assert_equal "api_error", doc.dig("error", "code")
    assert_nil doc["data"]
    assert_equal({ "changed" => false }, doc["meta"])
    assert_equal 0, @server.counts("POST", %r{/labels$})
  end

  def test_human_delete_reports_the_known_deletion
    out, err, status = planka("delete", "label", LABEL, "--board", BOARD)
    assert status.success?, err
    assert_includes out, "#{LABEL}"
    assert_includes out, "deleted: true"
  end

  def test_unknown_update_retains_identity_and_omitted_fields_but_not_uncertain_values
    @server.inject("PATCH", %r{/labels/}, :apply_then_drop)
    doc, err, status = json("update", "label", LABEL, "--board", BOARD, "--name", "changed")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_equal LABEL, doc.dig("data", "id")
    assert_nil doc.dig("data", "name")
    assert_equal "berry-red", doc.dig("data", "color")
    assert_equal "readback-label", doc.dig("error", "recovery", "action")
    assert_equal 1, @server.counts("PATCH", %r{/labels/})
    read, _, status = json("get", "label", LABEL, "--board", BOARD)
    assert_equal 0, status
    assert_equal "changed", read.dig("data", "name")
  end

  def test_unknown_delete_can_be_reconciled_through_a_read
    @server.inject("DELETE", %r{/labels/}, :apply_then_drop)
    doc, err, status = json("delete", "label", LABEL, "--board", BOARD)
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_nil doc.dig("meta", "changed")
    assert_nil doc.dig("data", "deleted")
    assert_equal LABEL, doc.dig("data", "id")
    assert_equal "readback-label", doc.dig("error", "recovery", "action")
    assert_equal 1, @server.counts("DELETE", %r{/labels/})
    read, _, status = json("get", "labels", "--board", BOARD)
    assert_equal 0, status
    assert_empty read["data"]
  end

  def test_rejected_writes_report_known_unchanged_state_and_cleanup
    [["create", "POST", ["--name", "new", "--color", "berry-red"]], ["update", "PATCH", [LABEL, "--name", "new"]], ["delete", "DELETE", [LABEL]]].each do |verb, method, arguments|
      @server.inject(method, %r{/labels(?:/|$)}, 403)
      doc, err, status = json(verb, "label", *arguments, "--board", BOARD)
      assert_equal 1, status, err
      assert_equal "authorization_error", doc.dig("error", "code")
      assert_equal false, doc.dig("meta", "changed")
      verb == "create" ? assert_nil(doc["data"]) : assert_equal("enhancement", doc.dig("data", "name"))
      assert_equal false, doc.dig("data", "deleted") if verb == "delete"
    end
    assert_equal 3, @server.counts("DELETE", %r{access-tokens/me$})
    doc, _, status = json("get", "label", LABEL, "--board", BOARD)
    assert_equal 0, status
    assert_equal "enhancement", doc.dig("data", "name")
  end

  def test_local_invalid_inputs_are_rejected_before_authentication
    commands = [
      ["get", "labels", "--limit", "0"],
      ["get", "labels", "--name", "one", "--name", "two"],
      ["get", "labels", "--member", "1"],
      ["get", "label", LABEL, "--name", "enhancement"],
      ["get", "label", "https://other.example/labels/1"],
      ["get", "labels", "--board", "https://other.example/boards/1"],
      ["create", "label", "--name", "new"],
      ["create", "label", "--name", " ", "--color", "berry-red"],
      ["create", "label", "--name", "x" * 129, "--color", "berry-red"],
      ["create", "label", "--name", "😀" * 65, "--color", "berry-red"],
      ["create", "label", "--name", "new", "--color", "invalid"],
      ["create", "label", "--name", "new", "--color", "berry-red", "--position", "-1"],
      ["create", "label", "--name", "new", "--color", "berry-red", "--position", "1e999"],
      ["update", "label", LABEL],
      ["update", "label", LABEL, "--name", ""],
      ["update", "label", LABEL, "--position", "NaN"],
      ["delete", "label"],
      ["delete", "label", LABEL, "--cascade"],
    ]
    commands.each do |arguments|
      doc, err, status = json(*arguments)
      assert_equal 2, status, "#{arguments.inspect}: #{err}"
      assert_equal "invalid_input", doc.dig("error", "code")
    end
    assert_empty @server.requests
  end

  def test_malformed_mutation_responses_preserve_known_ids_and_require_recovery
    returned = { "id" => "987", "boardId" => BOARD, "name" => "new", "color" => "invalid", "position" => nil }
    @server.inject("POST", %r{/labels$}, { "item" => returned })
    doc, err, status = json("create", "label", "--board", BOARD, "--name", "new", "--color", "berry-red")
    assert_equal 1, status, err
    assert_equal "unknown_outcome", doc.dig("error", "code")
    assert_equal "987", doc.dig("data", "id")
    assert_includes doc.dig("error", "recovery", "resources"), { "type" => "label", "id" => "987" }
    [["update", "PATCH", ["--name", "new"]], ["delete", "DELETE", []]].each do |verb, method, arguments|
      @server.inject(method, %r{/labels/}, { "item" => @server.labels.first.merge("id" => "999") })
      doc, err, status = json(verb, "label", LABEL, "--board", BOARD, *arguments)
      assert_equal 1, status, err
      assert_equal "unknown_outcome", doc.dig("error", "code")
      assert_nil doc.dig("meta", "changed")
      assert_equal LABEL, doc.dig("data", "id")
      assert_equal 1, @server.counts(method, %r{/labels/})
    end
  end

  def test_offline_help_exposes_all_label_verbs_and_aliases
    %w[get create update delete add remove].each do |verb|
      %w[label labels].each do |resource|
        out, err, status = planka(verb, resource, "--help", env: { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil })
        assert status.success?, err
        assert_includes out, "usage: planka #{verb} label"
      end
      out, err, status = planka(verb, "--help")
      assert status.success?, err
      assert_match(/^  labels? /, out)
    end
    assert_empty @server.requests
  end

  def test_reads_and_writes_preserve_the_primary_result_when_cleanup_fails
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    doc, err, status = json("get", "labels", "--board", BOARD)
    assert_equal 0, status
    assert_equal LABEL, doc.dig("data", 0, "id")
    assert_nil doc["error"]
    assert_includes err, "session cleanup failed"
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    doc, err, status = json("update", "label", LABEL, "--board", BOARD, "--color", "lagoon-blue")
    assert_equal 0, status
    assert_equal true, doc.dig("meta", "changed")
    assert_nil doc["error"]
    assert_includes err, "session cleanup failed"
    @server.inject("GET", %r{/boards/}, 403)
    @server.inject("DELETE", %r{access-tokens/me$}, 403)
    doc, _, status = json("get", "labels", "--board", BOARD)
    assert_equal 1, status
    assert_equal "authorization_error", doc.dig("error", "code")
    assert_equal [], doc["data"]
    assert_equal false, doc.dig("meta", "complete")
  end

  def test_legacy_label_commands_keep_their_bare_shapes_and_exact_name_reuse
    [nil, "planka-labels"].each do |direct|
      arguments = direct ? [] : ["labels"]
      out, err, status = planka(*arguments, "--board", BOARD, "--output", "json", direct: direct)
      assert status.success?, err
      doc = JSON.parse(out)
      assert_equal %w[boardId labels], doc.keys.sort
      assert_equal LABEL, doc.dig("labels", 0, "id")
    end
    [nil, "planka-create-label"].each do |direct|
      arguments = direct ? [] : ["create-label"]
      out, err, status = planka(*arguments, "--board", BOARD, "--name", "enhancement", "--output", "json", direct: direct)
      assert status.success?, err
      doc = JSON.parse(out)
      assert_equal false, doc["created"]
      assert_equal LABEL, doc.dig("label", "id")
    end
    [nil, "planka-apply-label"].each_with_index do |direct, index|
      arguments = direct ? [] : ["apply-label"]
      out, err, status = planka(*arguments, FakePlanka::PARENT_CARD, "--label", LABEL, "--output", "json", direct: direct)
      assert status.success?, err
      assert_equal({ "cardId" => FakePlanka::PARENT_CARD, "labelId" => LABEL, "created" => index.zero? }, JSON.parse(out))
    end
    assert_equal 0, @server.counts("POST", %r{/labels$})
  end
end
