module Planka
  # A resource role for attaching and detaching existing targets. Includers
  # provide these private messages in addition to Resource's CRUD hooks;
  # observations are opaque to this module:
  #   read_record(reference) -> fresh validated observation
  #   relationship_present?(observation) -> Boolean
  #   relationship_data(observation, present:) -> public data
  # Resource owns CRUD sequencing and write outcomes. Missing or ambiguous targets and
  # failed observations raise; only a known absent relationship returns false.
  module Relationship
    def include?(reference) = relationship_present?(read_record(reference))
    def add(reference) = create(reference)
    def remove(reference) = delete(reference)

    private

    def record_data(known) = relationship_data(known, present: relationship_present?(known))
    def creation_data(known, _attributes) = relationship_data(known, present: true)
    def deletion_data(known) = relationship_data(known, present: false)
  end
end
