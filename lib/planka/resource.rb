module Planka
  # Template algorithms for creating, updating, and deleting scoped records.
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

    def create(reference)
      known = read_record(reference)
      persist(known, creation_data(known)) { create_record(known) }
    end

    def update(reference, **attributes)
      attributes = update_attributes(**attributes)
      known = read_record(reference)
      persist(known, updated_data(known, attributes)) { update_record(known, attributes) }
    end

    def delete(reference)
      known = read_record(reference)
      persist(known, deletion_data(known)) { delete_record(known) }
    end

    private

    # Read hooks may return an opaque observation. Public state projections are
    # flat hashes; desired state retains known fields and changes requested ones.
    def record_data(known) = known
    def updated_data(known, attributes) = record_data(known).merge(attributes)
    def confirmed_data(_record, desired) = desired

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
