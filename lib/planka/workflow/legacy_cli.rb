require "planka/workflow/format"

module Planka
  module CLI
    # Historical CLI formatting entry points delegate to workflow presentation.
    module_function
    def ticket_result(...) = Workflow::Format.ticket_result(...)
    def card_ref(...) = Workflow::Format.card_ref(...)
    def next_card(...) = Workflow::Format.next_card(...)
    def blocker_ref(...) = Workflow::Format.blocker_ref(...)
    def pending_criteria(...) = Workflow::Format.pending_criteria(...)
    def branch_name(...) = Workflow::Format.branch_name(...)
  end
end
