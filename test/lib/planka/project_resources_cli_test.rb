require "minitest/autorun"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "fake_project_planka"

class ProjectResourcesCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  PROJECT = "100000000000000010".freeze

  def setup = @server = FakeProjectPlanka.new
  def teardown = @server.stop

  def planka(*args, env: {}, stdin_data: "", executable: "planka")
    settings = { "PLANKA_BASE_URL" => @server.base_url, "PLANKA_AGENT_EMAIL" => "bot@example.com",
                 "PLANKA_AGENT_PASSWORD" => "fake-password", "PLANKA_BOARD_ID" => "ignored" }
    out, err, status = Open3.capture3(settings.merge(env), RbConfig.ruby, "-I#{ROOT}/lib", "#{ROOT}/exe/#{executable}", *args,
                                      stdin_data: stdin_data, chdir: Dir.tmpdir)
    [out.force_encoding(Encoding::UTF_8), err.force_encoding(Encoding::UTF_8), status]
  end

  def json(*args, **options)
    out, err, status = planka(*args, "-o", "json", **options)
    [JSON.parse(out), err, status]
  end

  def writes
    @server.requests.reject { |method, path, _| method == "GET" || path.include?("access-tokens") }
           .map { |method, path, body| [method, path, body.empty? ? nil : JSON.parse(body)] }
  end

  def project(overrides = {})
    { "id" => PROJECT, "name" => "Product", "description" => "A roadmap", "ownerProjectManagerId" => "900",
      "createdAt" => nil, "updatedAt" => nil }.merge(overrides)
  end

  def expected_project(overrides = {})
    record = project(overrides)
    record.merge("type" => record["ownerProjectManagerId"] ? "private" : "shared", "url" => "#{@server.base_url}/projects/#{record["id"]}")
  end

  def test_collection_reads_accessible_projects_with_exact_filter_before_limit
    records = [project("id" => "11", "name" => "Other"), project, project("id" => "12")]
    3.times { @server.inject("GET", %r{/api/projects\z}, { "items" => records, "included" => {} }) }
    doc, err, status = json("get", "projects", "--name", "Product", "--limit", "1")
    assert status.success?, err
    assert_equal({ "data" => [expected_project], "meta" => { "complete" => false }, "error" => nil }, doc)
    doc, err, status = json("get", "project", "--name", "Product", "--limit", "2")
    assert status.success?, err
    assert_equal([PROJECT, "12"], doc["data"].map { |record| record["id"] })
    assert_equal true, doc.dig("meta", "complete")
    out, err, status = planka("get", "projects", "--limit", "1")
    assert status.success?, err
    assert_includes out, "Other (11)"
    assert_includes out, "Results truncated"
    assert_empty writes
    assert_equal 3, @server.counts("GET", %r{/api/projects\z})
    assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
  end

  def test_individual_reads_accept_ids_same_instance_urls_and_exact_names
    [PROJECT, "#{@server.base_url}/projects/#{PROJECT}", "Product"].each do |reference|
      @server.inject("GET", %r{/api/projects\z}, { "items" => [project], "included" => {} }) if reference == "Product"
      @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, { "item" => project, "included" => {} })
      doc, err, status = json("get", "project", reference)
      assert status.success?, err
      assert_equal({ "data" => expected_project, "meta" => {}, "error" => nil }, doc)
    end
    @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, { "item" => project, "included" => {} })
    out, err, status = planka("get", "projects", PROJECT)
    assert status.success?, err
    assert_equal "Product (#{PROJECT}) #{@server.base_url}/projects/#{PROJECT}\n", out
    assert_empty writes
  end

  def test_create_defaults_to_private_preserves_native_ownership_and_omits_unsupplied_description
    doc, err, status = json("create", "project", "--name", "New")
    assert status.success?, err
    assert_equal({ "changed" => true }, doc["meta"])
    assert_nil doc["error"]
    assert_equal "New", doc.dig("data", "name")
    assert_nil doc.dig("data", "description")
    assert_match(/\A\d+\z/, doc.dig("data", "ownerProjectManagerId"))
    assert_equal [["POST", "/api/projects", { "type" => "private", "name" => "New" }]], writes
    read, err, status = json("get", "project", doc.dig("data", "id"))
    assert status.success?, err
    assert_equal doc["data"], read["data"]
  end

  def test_shared_creation_accepts_inline_file_or_stdin_descriptions_without_manager_writes
    text = "Ünicode \"quote\"\nSecond line 😀"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "description.txt")
      File.write(path, text)
      [["--description", text], ["--description-file", path], ["--description-file", "-"]].each do |description|
        @server.requests.clear
        doc, err, status = json("create", "projects", "--name", "Product", "--type", "shared", *description, stdin_data: text)
        assert status.success?, err
        assert_equal ["shared", nil, text], doc["data"].values_at("type", "ownerProjectManagerId", "description")
        assert_equal [["POST", "/api/projects", { "name" => "Product", "type" => "shared", "description" => text }]], writes
      end
    end
  end

  def test_updates_change_supplied_fields_only_allow_explicit_clearing_and_skip_identical_values
    doc, err, status = json("update", "project", PROJECT, "--name", "Renamed")
    assert status.success?, err
    assert_equal({ "data" => expected_project("name" => "Renamed"), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["PATCH", "/api/projects/#{PROJECT}", { "name" => "Renamed" }]], writes
    @server.requests.clear
    doc, err, status = json("update", "projects", "Renamed", "--name", "Renamed", "--clear-description")
    assert status.success?, err
    assert_equal expected_project("name" => "Renamed", "description" => nil), doc["data"]
    assert_equal [["PATCH", "/api/projects/#{PROJECT}", { "description" => nil }]], writes
    @server.requests.clear
    doc, err, status = json("update", "project", PROJECT, "--clear-description")
    assert status.success?, err
    assert_equal false, doc.dig("meta", "changed")
    assert_empty writes
    doc, err, status = json("update", "project", PROJECT, "--description-file", "-", stdin_data: "Restored\n😀")
    assert status.success?, err
    assert_equal "Restored\n😀", doc.dig("data", "description")
    read, err, status = json("get", "project", PROJECT)
    assert status.success?, err
    assert_equal doc["data"], read["data"]
  end

  def test_delete_sends_only_the_target_delete_and_preserves_native_nonempty_rejection
    @server.boards.first["projectId"] = PROJECT
    doc, _err, status = json("delete", "project", PROJECT)
    assert_equal 1, status.exitstatus
    assert_equal false, doc.dig("meta", "changed")
    assert_equal expected_project, doc["data"]
    assert_equal [["DELETE", "/api/projects/#{PROJECT}", nil]], writes
    @server.boards.clear
    @server.requests.clear
    doc, err, status = json("delete", "projects", "Product")
    assert status.success?, err
    assert_equal({ "data" => expected_project("deleted" => true), "meta" => { "changed" => true }, "error" => nil }, doc)
    assert_equal [["DELETE", "/api/projects/#{PROJECT}", nil]], writes
    read, _err, status = json("get", "project", PROJECT)
    assert_equal [1, "not_found"], [status.exitstatus, read.dig("error", "code")]
  end

  def test_uncertain_creates_are_not_retried_and_retain_only_a_valid_returned_identity
    [[:apply_then_drop, nil], [{ "item" => { "id" => "71" } }, "71"],
     [{ "item" => { "id" => "../unsafe" } }, nil]].each do |response, returned_id|
      @server.requests.clear
      @server.inject("POST", %r{/api/projects\z}, response)
      doc, _err, status = json("create", "project", "--name", "Uncertain")
      assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
      assert_equal returned_id, doc.dig("data", "id") if returned_id
      assert_nil doc.dig("data", "id") unless returned_id
      assert_nil doc.dig("data", "name")
      resources = returned_id ? [{ "type" => "project", "id" => returned_id }] : []
      action = returned_id ? "readback-project" : "readback-projects"
      assert_equal({ "action" => action, "resources" => resources }, doc.dig("error", "recovery"))
      assert_equal 1, writes.size
      assert_equal ["DELETE", "/api/access-tokens/me"], @server.requests.last.first(2)
    end
  end

  def test_help_explains_each_command_offline_at_root_group_and_leaf_levels
    offline = { "PLANKA_BASE_URL" => nil, "PLANKA_AGENT_EMAIL" => nil, "PLANKA_AGENT_PASSWORD" => nil }
    { [] => "create project --name NAME", %w[--help] => "delete project PROJECT",
      %w[get --help] => "project PROJECT", %w[create --help] => "project --name NAME",
      %w[update --help] => "project PROJECT", %w[delete --help] => "project PROJECT",
      %w[get projects --help] => "exact name on this instance", %w[get project -h] => "meta.complete",
      %w[create projects --help] => "default private", %w[create project -h] => "readback-projects",
      %w[update projects --help] => "--clear-description sends null", %w[update project -h] => "1024",
      %w[delete projects --help] => "rejects projects with boards", %w[delete project -h] => "readback-project" }.each do |args, text|
      out, err, status = planka(*args, env: offline)
      assert status.success?, "#{args.inspect}: #{err}"
      assert_includes out, text, args.inspect
    end
    assert_empty @server.requests
  end

  def test_invalid_inputs_are_rejected_before_authentication
    [["create", "project"], ["create", "project", "--name", ""], ["create", "project", "--name", "x" * 129],
     ["create", "project", "--name", "😀" * 65], ["create", "project", "--name", "x", "--type", "public"],
     ["create", "project", "--name", "x", "--clear-description"], ["create", "project", PROJECT, "--name", "x"],
     ["create", "project", "--name", "x", "--description", ""], ["create", "project", "--name", "x", "--description", "x" * 1025],
     ["create", "project", "--name", "x", "--description", "😀" * 513],
     ["create", "project", "--name", "a", "--name", "b"],
     ["update", "project", PROJECT], ["update", "project", "--name", "x"],
     ["update", "project", PROJECT, "--type", "shared"], ["update", "project", PROJECT, "--owner", "1"],
     ["update", "project", PROJECT, "--description", "text", "--clear-description"],
     ["update", "project", PROJECT, "--description", "text", "--description-file", "-"],
     ["update", "project", PROJECT, "--description-file", "-", "--clear-description"],
     ["update", "project", PROJECT, "--description-file", "/no/such/project-description"],
     ["update", "project", PROJECT, "--description-file", "-"],
     ["delete", "project"], ["delete", "project", PROJECT, "--cascade"],
     ["get", "project", "https://elsewhere.example/projects/1"], ["get", "project", "/projects/1"],
     ["get", "project", PROJECT, "--name", "Product"], ["get", "project", PROJECT, "--limit", "1"],
     ["get", "projects", "--board", "1"], ["get", "projects", "--project", PROJECT],
     ["get", "projects", "--label", "x"], ["get", "projects", "--member", "x"],
     ["get", "projects", "--limit", "0"], ["get", "projects", "--limit", "1.5"]].each do |args|
      doc, _err, status = json(*args)
      assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")], args.inspect
    end
    assert_empty @server.requests
  end

  def test_malformed_collections_preserve_only_valid_matching_records_and_never_claim_completeness
    [project("id" => "../unsafe"), project("name" => 7), project("description" => false),
     project.except("ownerProjectManagerId"), project("createdAt" => "bad"), project].each do |invalid|
      @server.inject("GET", %r{/api/projects\z}, { "items" => [project, invalid], "included" => {} })
      doc, _err, status = json("get", "projects", "--name", "Product", "--limit", "1")
      assert_equal [1, "api_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "complete")]
      assert_equal [expected_project], doc["data"]
    end
    [nil, {}, "invalid"].each do |items|
      @server.inject("GET", %r{/api/projects\z}, { "items" => items })
      doc, _err, status = json("get", "projects")
      assert_equal [1, [], false, "api_error"], [status.exitstatus, doc["data"], doc.dig("meta", "complete"), doc.dig("error", "code")]
    end
    assert_empty writes
  end

  def test_updates_preserve_observed_fields_and_report_rejected_or_uncertain_effects_without_retry
    [[403, "authorization_error", false, expected_project],
     [{ "item" => project("name" => "Renamed", "ownerProjectManagerId" => "901") }, "unknown_outcome", nil, expected_project("name" => nil)],
     [{ "item" => project("id" => "999", "name" => "Renamed") }, "unknown_outcome", nil, expected_project("name" => nil)],
     [:apply_then_drop, "unknown_outcome", nil, expected_project("name" => nil)]].each do |response, code, changed, data|
      @server.requests.clear
      @server.inject("PATCH", %r{/api/projects/#{PROJECT}\z}, response)
      doc, _err, status = json("update", "project", PROJECT, "--name", "Renamed")
      assert_equal [1, code, changed, data], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
      assert_equal({ "action" => "readback-project", "resources" => [{ "type" => "project", "id" => PROJECT }] }, doc.dig("error", "recovery"))
      assert_equal [["PATCH", "/api/projects/#{PROJECT}", { "name" => "Renamed" }]], writes
    end
  end

  def test_missing_ambiguous_and_malformed_individual_reads_return_operational_errors_without_writes
    @server.projects << project("id" => "12")
    doc, _err, status = json("get", "project", "Product")
    assert_equal [1, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
    assert_includes doc.dig("error", "message"), PROJECT
    assert_includes doc.dig("error", "message"), "12"
    ["Missing", "999"].each do |reference|
      doc, _err, status = json("get", "project", reference)
      assert_equal [1, "not_found"], [status.exitstatus, doc.dig("error", "code")]
    end
    [{ "item" => nil }, { "item" => project("id" => "999") }, { "item" => project("name" => false) }].each do |response|
      @server.inject("GET", %r{/api/projects/#{PROJECT}\z}, response)
      doc, _err, status = json("get", "project", PROJECT)
      assert_equal [1, nil, "api_error"], [status.exitstatus, doc["data"], doc.dig("error", "code")]
    end
    @server.inject("GET", %r{/api/projects\z}, { "items" => [project, project("name" => 7)] })
    doc, _err, status = json("get", "project", "Product")
    assert_equal [1, nil, "api_error"], [status.exitstatus, doc["data"], doc.dig("error", "code")]
    assert_empty writes
  end

  def test_unknown_deletes_keep_identity_and_cleanup_failure_preserves_the_primary_outcome
    @server.inject("DELETE", %r{/api/projects/#{PROJECT}\z}, { "item" => project("id" => "999") })
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 500)
    doc, err, status = json("delete", "project", PROJECT)
    assert_equal [1, "unknown_outcome", nil, expected_project("deleted" => nil)],
                 [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed"), doc["data"]]
    assert_includes err, "session cleanup failed"
    @server.requests.clear
    @server.inject("DELETE", %r{/api/projects/#{PROJECT}\z}, :apply_then_drop)
    doc, _err, status = json("delete", "project", PROJECT)
    assert_equal [1, "unknown_outcome", nil], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_equal({ "action" => "readback-project", "resources" => [{ "type" => "project", "id" => PROJECT }] }, doc.dig("error", "recovery"))
    assert_equal [["DELETE", "/api/projects/#{PROJECT}", nil]], writes
    @server.inject("DELETE", %r{/api/access-tokens/me\z}, 500)
    doc, err, status = json("create", "project", "--name", "Kept")
    assert status.success?, err
    assert_equal [true, "Kept"], [doc.dig("meta", "changed"), doc.dig("data", "name")]
    assert_includes err, "operation result is unchanged"
  end

  def test_required_configuration_and_authentication_failures_prevent_resource_requests
    [%w[get projects], ["get", "project", PROJECT], %w[create project --name New],
     ["update", "project", PROJECT, "--name", "New"], ["delete", "project", PROJECT]].each do |args|
      %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].each do |key|
        doc, _err, status = json(*args, env: { key => nil })
        assert_equal [1, "configuration_error"], [status.exitstatus, doc.dig("error", "code")], "#{args.inspect}: #{key}"
      end
    end
    assert_empty @server.requests
    @server.inject("POST", %r{/api/access-tokens\z}, 401)
    doc, err, status = json("create", "project", "--name", "New")
    assert_equal [1, "authentication_error", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    refute_includes err, "fake-password"
    refute_includes err, "private upstream body"
    assert_empty writes
    @server.requests.clear
    @server.inject("POST", %r{/api/projects\z}, 404)
    doc, _err, status = json("create", "project", "--name", "Denied")
    assert_equal [1, "not_found", false], [status.exitstatus, doc.dig("error", "code"), doc.dig("meta", "changed")]
    assert_nil doc.dig("data", "id")
    assert_equal 1, writes.size
  end

  def test_description_files_reject_invalid_text_and_accept_native_unicode_limits_without_truncation
    Dir.mktmpdir do |dir|
      path = File.join(dir, "description.txt")
      ["", " \n", "x" * 1025, "\xFF".b].each do |text|
        File.binwrite(path, text)
        doc, _err, status = json("update", "project", PROJECT, "--description-file", path)
        assert_equal [2, "invalid_input"], [status.exitstatus, doc.dig("error", "code")]
      end
      assert_empty @server.requests
      text = "😀" * 512
      File.write(path, text)
      doc, err, status = json("create", "project", "--name", "😀" * 64, "--description-file", path)
      assert status.success?, err
      assert_equal ["😀" * 64, text], doc["data"].values_at("name", "description")
      doc, err, status = json("update", "project", PROJECT, "--description", "Inline\nupdated")
      assert status.success?, err
      assert_equal "Inline\nupdated", doc.dig("data", "description")
    end
  end

  def test_empty_filtered_projects_are_successful_and_human_mutations_identify_the_resource
    doc, err, status = json("get", "projects", "--name", "product")
    assert status.success?, err
    assert_equal({ "data" => [], "meta" => { "complete" => true }, "error" => nil }, doc)
    out, err, status = planka("get", "projects", "--name", "missing")
    assert status.success?, err
    assert_equal "No projects.\n", out
    out, err, status = planka("create", "projects", "--name", "Another")
    assert status.success?, err
    assert_match(/Created project Another \(\d+\) http/, out)
    out, err, status = planka("update", "projects", "Product", "--name", "Changed")
    assert status.success?, err
    assert_includes out, "Updated project Changed (#{PROJECT})"
    out, err, status = planka("delete", "project", "Changed")
    assert status.success?, err
    assert_includes out, "Deleted project Changed (#{PROJECT})"
  end

  def test_legacy_snapshot_flat_and_direct_executables_keep_the_same_bare_json
    env = { "PLANKA_BOARD_ID" => FakePlanka::BOARD_ID }
    out, err, status = planka("snapshot", "-o", "json", env: env)
    assert status.success?, err
    direct, direct_err, direct_status = planka("-o", "json", env: env, executable: "planka-snapshot")
    assert direct_status.success?, direct_err
    assert_equal out, direct
    refute JSON.parse(out).key?("meta")
    assert_empty err
    assert_empty direct_err
    assert_empty writes
  end
end
