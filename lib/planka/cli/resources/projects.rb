require "planka"
require "planka/cli/command"
require "planka/cli/failure"
require "planka/cli/input_file"
require "planka/cli/resources/scalar_flags"

module Planka
  module CLI
    module Resources
      module Projects
        ROOT_HELP = <<~HELP.gsub(/^/, "  ")
          get projects  List accessible projects (read-only)
          get project PROJECT  Read one concise project (read-only)
          create project --name NAME  Create a private or shared project
          update project PROJECT  Change supplied name/description fields
          delete project PROJECT  Delete one empty project
        HELP
        GROUP_HELP = {
          "get" => "  projects  List accessible projects (read-only)\n  project PROJECT  Read one concise project (read-only)\n",
          "create" => "  project --name NAME  Create a private or shared project\n",
          "update" => "  project PROJECT  Change supplied name/description fields\n",
          "delete" => "  project PROJECT  Delete one empty project\n",
        }.freeze
        COMMON_HELP = <<~HELP
          PROJECT is a numeric ID, same-instance project URL, or exact name on this instance among accessible
          projects. Ambiguous names report candidate IDs. No board or other parent scope is used.
          Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD; session tokens stay in memory.
          project/projects are aliases. Success exits 0, local input 2, operational failures 1.
          JSON uses data/meta/error. Project fields: id, name, description, type, ownerProjectManagerId,
          createdAt, updatedAt, url. Type is private when an owner exists, shared otherwise.
        HELP
        GET_HELP = <<~HELP + COMMON_HELP
          usage: planka get projects [--name NAME] [--limit N] [-o human|json]
                 planka get project PROJECT [-o human|json]
          Read all projects accessible to the signed-in user from one native response, without paging.
          Preserve response order; exact --name filtering precedes a positive --limit. Filters/limits are
          collection-only; label/member and parent filters are unsupported. Collection data is an array with
          meta.complete, false when truncated or retrieval fails; failures keep matching records read so far.
          Individual data is an object with empty meta. Managers and board members can read their projects;
          administrators can also read shared projects. Native access denial can appear as not_found.
        HELP
        CREATE_HELP = <<~HELP + COMMON_HELP
          usage: planka create project --name NAME [--type private|shared]
                                       [--description TEXT | --description-file FILE|-] [-o human|json]
          Always create, even if a name exists; default private. Native administrator or projectOwner role is
          required. Planka creates the caller's manager relationship and makes it owner for a private project;
          no extra client manager writes. NAME is nonempty, at most 128 UTF-16 code units. Description is optional,
          nonempty text at most 1024 UTF-16 code units; omitted description remains null. File - reads stdin.
          Description input is read and validated before requests; --clear-description is update-only.
          Data is the resulting project; meta.changed is true, false on rejection, null for unknown outcomes.
          Unknown/malformed writes are never retried. readback-projects with no resource ID means inspect
          planka get projects before retrying. A valid returned ID is retained with readback-project recovery.
        HELP
        UPDATE_HELP = <<~HELP + COMMON_HELP
          usage: planka update project PROJECT [--name NAME]
                                       [--description TEXT | --description-file FILE|- | --clear-description] [-o human|json]
          Change supplied fields only; at least one is required. Identical values are a no-op. Native project
          manager permission is required. NAME is nonempty, at most 128 UTF-16 code units. Description is nonempty
          text at most 1024 UTF-16 code units; file - reads stdin. --clear-description sends null; omitted
          description stays unchanged. Inputs are read/validated before requests. Type/ownership, backgrounds,
          visibility and favorites are not editable here. Data is the resulting project; meta.changed is
          true/false/null. Rejections keep observed state; unknown responses mark changed fields null and give
          readback-project recovery. Read back with planka get project PROJECT before retrying.
        HELP
        DELETE_HELP = <<~HELP + COMMON_HELP
          usage: planka delete project PROJECT [-o human|json]
          Send one target DELETE without prompts. Native project manager permission is required. Planka
          rejects projects with boards; the client does not delete boards or children to bypass this rule.
          Successful native deletion cleans up project relationships and settings. Data is the observed project
          with deleted true; meta.changed is true/false/null. Rejections keep observed state without deleted;
          unknown/malformed responses set deleted null and give readback-project recovery. Read back with
          planka get project PROJECT before retrying. An omitted target is an input error, never a bulk delete.
        HELP

        def self.prepare_get(_env, instance:, flags:, reference:)
          return { base_url: instance.base_url } if reference

          { base_url: instance.base_url, name: flags[:name]&.first, limit: flags[:limit]&.first&.to_i }
        end

        def self.get(client, reference = nil, base_url:, **collection)
          projects = Planka::Projects.new(client, base_url: base_url)
          reference ? projects.find(reference) : projects.all(**collection)
        end

        def self.format_project(project) = "#{project["name"]} (#{project["id"]}) #{project["url"]}"

        def self.format_projects(data)
          return format_project(data) if data.is_a?(Hash)

          data.empty? ? "No projects." : data.map { |project| format_project(project) }.join("\n")
        end

        def self.prepare_create(_env, instance:, flags:, **)
          raise Failure.invalid_input("create project requires --name") unless flags[:name]

          { base_url: instance.base_url, name: flags[:name].first, type: flags[:type]&.first || "private".freeze, description: description(flags) }
        end

        def self.description(flags)
          text = flags[:description_file] ? InputFile.read(flags[:description_file].first) : flags[:description]&.first
          Planka::Projects::Record.description!(text).freeze
        rescue ArgumentError => error
          raise Failure.invalid_input(error.message)
        rescue SystemCallError, IOError
          raise Failure.invalid_input("Could not read --description-file")
        end
        private_class_method :description

        def self.validate_values(flags)
          error = ScalarFlags.error(flags)
          return error if error

          return "Description inputs conflict" if flags.keys.intersection([:description, :description_file, :clear_description]).size > 1

          Planka::Projects::Record.name!(flags[:name].first) if flags[:name]
          Planka::Projects::Record.type!(flags[:type].first) if flags[:type]
          nil
        rescue ArgumentError => error
          error.message
        end

        def self.create(client, base_url:, **attributes) = Planka::Projects.new(client, base_url: base_url).create(**attributes)

        def self.prepare_update(_env, instance:, flags:, **)
          attributes = {}
          attributes[:name] = flags[:name].first if flags[:name]
          attributes[:description] = description(flags) if flags[:description] || flags[:description_file] || flags[:clear_description]
          raise Failure.invalid_input("update project requires --name, --description, --description-file, or --clear-description") if attributes.empty?

          attributes.merge(base_url: instance.base_url)
        end

        def self.update(client, reference, base_url:, **attributes) = Planka::Projects.new(client, base_url: base_url).update(reference, **attributes)

        def self.delete(client, reference, base_url:) = Planka::Projects.new(client, base_url: base_url).delete(reference)

        COMMANDS = {
          ["delete", "project"] => Command.new(aliases: [["delete", "projects"]], names: true, mutation: true,
                                               resource: "project", collection: "projects", help: DELETE_HELP,
                                               operation: method(:delete), formatter: ->(project) { "Deleted project #{format_project(project)}" }),
          ["update", "project"] => Command.new(aliases: [["update", "projects"]], names: true, mutation: true,
                                               resource: "project", collection: "projects",
                                               flags: { "--name NAME" => :name, "--description TEXT" => :description,
                                                        "--description-file FILE|-" => :description_file, "--clear-description" => :clear_description },
                                               validate_flags: method(:validate_values), prepare: method(:prepare_update),
                                               help: UPDATE_HELP,
                                               operation: method(:update), formatter: ->(project) { "Updated project #{format_project(project)}" }),
          ["create", "project"] => Command.new(aliases: [["create", "projects"]], reference: false, mutation: true,
                                               resource: "project", collection: "projects",
                                               flags: { "--name NAME" => :name, "--type TYPE" => :type,
                                                        "--description TEXT" => :description, "--description-file FILE|-" => :description_file },
                                               validate_flags: method(:validate_values), prepare: method(:prepare_create),
                                               help: CREATE_HELP, operation: method(:create),
                                               formatter: ->(project) { "Created project #{format_project(project)}" }),
          ["get", "project"] => Command.new(aliases: [["get", "projects"]], names: true, optional_reference: true, collection_read: true,
                                            resource: "project", collection: "projects", collection_flags: [:name, :limit],
                                            flags: { "--name NAME" => :name, "--limit N" => :limit },
                                            validate_flags: ScalarFlags.method(:error), prepare: method(:prepare_get),
                                            help: GET_HELP, operation: method(:get), formatter: method(:format_projects)),
        }.freeze

        def self.commands = COMMANDS
        def self.root_help = ROOT_HELP
      end
    end
  end
end
