module Planka
  # Template algorithms for creating, updating, deleting, and reading collections
  # of scoped records.
  # Concrete resources expose supported verbs and supply lookup, request,
  # validation, and projection hooks; see the resource operations contract in
  # docs/CLI_REDESIGN_IMPLEMENTATION.md. Reads/input validation precede writes;
  # response validation and confirmed projection stay inside Write's boundary.
  class Resource
    def initialize(client)
      @client = client
    end

    protected

    attr_reader :client

    def create(reference, **attributes)
      attributes = creation_attributes(**attributes)
      known = read_creation_scope(reference)
      desired = creation_data(known, attributes)
      persist(known, desired) { create_record(known, desired) }
    end

    def update(reference, **attributes)
      attributes = update_attributes(**attributes)
      known = read_record(reference)
      desired = updated_data(known, attributes)
      persist(known, desired) { update_record(known, desired) }
    end

    def delete(reference)
      known = read_record(reference)
      persist(known, deletion_data(known)) { delete_record(known) }
    end

    private

    # Read hooks may return an opaque observation. Public state projections are
    # flat hashes; desired state retains known fields and changes requested ones.
    # A creation observes the scope it creates in, which is the target itself for
    # relationships and the parent for a new resource.
    def creation_attributes(**attributes) = attributes
    def read_creation_scope(reference) = read_record(reference)
    def record_data(known) = known
    def updated_data(known, attributes) = record_data(known).merge(attributes)
    def confirmed_data(_record, desired) = desired

    # Reads a collection into DATA, at most LIMIT records after PROJECT. A
    # failed read keeps the projected records read so far; reference failures
    # are input errors and propagate unchanged.
    def collect(limit, project: :itself.to_proc)
      data = []
      yield data
      CollectionResult.limited(project.call(data), limit)
    rescue *OPERATION_ERRORS => error
      raise if error.is_a?(ReferenceError)

      raise CollectionFailure.new(data: CollectionResult.limited(project.call(data), limit).data)
    end

    def persist(known, desired)
      unchanged = record_data(known)
      return MutationResult.new(data: desired, changed: false) if unchanged == desired

      Write.perform(unchanged: unchanged, unknown: uncertain_data(unchanged, desired), recovery: recovery(known)) do
        confirm(yield, desired)
      end
    end

    def uncertain_data(unchanged, desired)
      changes = desired.reject { |key, value| unchanged.key?(key) && unchanged[key] == value }
      unchanged.merge(changes.transform_values { nil })
    end

    def confirm(record, desired)
      validate_record!(record, desired)
      confirmed_data(record, desired)
    end
  end
end
