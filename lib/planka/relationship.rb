module Planka
  # A resource role for attaching and detaching existing targets. Includers
  # provide these private messages; observations are opaque to this module:
  #   observe_relationship(reference) -> fresh validated observation
  #   relationship_present?(observation) -> Boolean
  #   relationship_data(observation, present:) -> public data (nil = unknown)
  #   relationship_recovery(observation) -> readback guidance
  #   write_relationship(observation, present:) -> validated public data
  # Resource#mutate owns no-op/results/failures. Missing or ambiguous targets and
  # failed observations raise; only a known absent relationship returns false.
  module Relationship
    def include?(reference) = relationship_present?(observe_relationship(reference))
    def add(reference) = change_relationship(reference, present: true)
    def remove(reference) = change_relationship(reference, present: false)

    private

    def change_relationship(reference, present:)
      observation = observe_relationship(reference)
      mutate(unchanged: relationship_data(observation, present: relationship_present?(observation)),
             desired: relationship_data(observation, present: present),
             unknown: relationship_data(observation, present: nil),
             recovery: relationship_recovery(observation)) do
        write_relationship(observation, present: present)
      end
    end
  end
end
