module Planka
  # Native projects visible to the authenticated user on one instance.
  class Projects < Resource
    def initialize(client, base_url:)
      super(client)
      @base_url = base_url
    end

    def find(reference)
      id = Records.id?(reference) ? reference : resolve_name(reference)
      record = Record.data(client.project(id), base_url: @base_url)
      raise InvalidResponse, "Invalid project identity" unless record["id"] == id

      record
    end

    def create(name:, type: "private", description: nil) = super(nil, name: name, type: type, description: description)

    # Description nil explicitly clears it; omitted fields stay unchanged.
    public :update, :delete

    def all(name: nil, limit: nil)
      validate_options!(name: name, limit: limit)
      collect(limit) do |data|
        each_project { |project| data << project if name.nil? || project["name"] == name }
      end
    end

    private

    def validate_options!(name:, limit:)
      raise ArgumentError, "name must be a string" unless name.nil? || name.is_a?(String)
      raise ArgumentError, "limit must be a positive integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
    end

    def each_project
      seen = {}
      client.projects.each do |record|
        project = Record.data(record, base_url: @base_url)
        raise InvalidResponse, "Duplicate project record" if seen[project["id"]]

        seen[project["id"]] = true
        yield project
      end
    end

    def read_record(reference) = find(reference)

    def update_attributes(**attributes)
      raise ArgumentError, "supply a name or description" if attributes.empty?

      rules = { name: Record.method(:name!), description: Record.method(:description!) }
      attributes.to_h { |field, value| [field.to_s, rules.fetch(field) { raise ArgumentError, "unknown project field #{field}" }.call(value)] }
    end

    def deletion_data(known) = known.merge("deleted" => true)
    def delete_record(known) = client.delete_project(known["id"])

    def update_record(known, desired)
      changed = desired.slice("name", "description").reject { |field, value| known[field] == value }
      client.update_project(known["id"], **changed.transform_keys(&:to_sym))
    end

    def creation_attributes(name:, type:, description:)
      { "name" => Record.name!(name), "type" => Record.type!(type), "description" => Record.description!(description) }
    end

    def read_creation_scope(_reference) = Record.placeholder
    def creation_data(known, attributes) = known.merge(attributes)
    def create_record(_known, desired) = client.create_project(**desired.slice("name", "type", "description").compact.transform_keys(&:to_sym))
    def validate_record!(record, desired, **) = Record.confirm!(record, desired, base_url: @base_url)
    def confirmed_data(record, desired) = Record.data(record, base_url: @base_url).merge(desired.slice("deleted"))
    def recovery(known) = Record.recovery(known)

    def unconfirmed_data(known, desired, returned)
      data = super
      known["id"] ? data : data.merge("id" => Record.returned_id(returned))
    end

    def unconfirmed_recovery(known, desired, returned) = Record.recovery(unconfirmed_data(known, desired, returned))

    def resolve_name(reference)
      matches = all(name: reference).data
      raise ReferenceError.new("Project not found on this instance", code: "not_found", status: 1) if matches.empty?
      if matches.size > 1
        raise ReferenceError.new("Ambiguous project name; candidate IDs: #{matches.map { |record| record["id"] }.join(", ")}", status: 1)
      end

      matches.first["id"]
    rescue CollectionFailure => error
      # Lookup has not identified an individual resource; collection partials
      # are not that resource's data. Preserve the original failure category.
      raise error.cause
    end
  end
end
