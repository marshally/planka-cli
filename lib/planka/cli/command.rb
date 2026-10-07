module Planka
  module CLI
    # One canonical command definition. Optional behavior defaults live here, so
    # parsing, preparation and output ask the command instead of re-applying them.
    Command = Data.define(:help, :operation, :formatter, :resource, :collection, :aliases, :flags,
                          :reference, :optional_reference, :names, :session, :mutation, :collection_read, :collection_flags,
                          :prepare, :validate_flags, :projector) do
      def initialize(aliases: [], flags: {}, reference: true, optional_reference: false, names: false,
                     session: true, mutation: false, collection_read: false, collection_flags: [],
                     resource: nil, collection: nil, prepare: nil, validate_flags: nil, projector: nil, **required)
        super(aliases: aliases.map { |path| path.dup.freeze }.freeze, flags: flags.dup.freeze,
              collection_flags: collection_flags.dup.freeze, reference:, optional_reference:, names:, session:,
              mutation:, collection_read:, resource:, collection:, prepare:, validate_flags:, projector:, **required)
      end

      def reference? = reference
      def optional_reference? = optional_reference
      # Whether a reference may be an exact name rather than an ID or URL.
      def names? = names
      def session? = session
      def mutation? = mutation
      def collection_read? = collection_read
      def flag_keys = flags.values
      def flag_error(values) = validate_flags&.call(values)

      def preparation(env, instance:, flags:, reference: nil)
        prepare ? prepare.call(env, instance:, flags:, reference:) : { base_url: instance.base_url }
      end

      def project(data) = projector ? projector.call(data) : data
      def format(data) = formatter.call(data)
    end
  end
end
