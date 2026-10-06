require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Cards
        module Labels
          ROOT_HELP = <<~HELP.gsub(/^/, "  ")
              add label LABEL --card CARD  Add one existing board label to a card
              remove label LABEL --card CARD  Detach only this label from a card
          HELP
          COMMON_HELP = <<~HELP
            LABEL is an ID or exact label name on the card's board.
            CARD is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
            Explicit card IDs/URLs ignore the default board; --board asserts the actual parent.
            Ambiguous names report candidate IDs. BOARD is an ID or same-instance URL.
            Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
            Success exits 0, local input 2, operational failures 1.
            No workflow convention or label mutation. All resource commands preserve unrelated labels.
          HELP
          ADD_HELP = <<~HELP + COMMON_HELP
            usage: planka add label LABEL --card CARD [--board BOARD] [-o human|json]
            Add an existing board label; an existing association is a no-op.
            JSON uses data/meta/error with cardId, labelId, and present; meta.changed is true/false/null.
            A lost/malformed write response gives readback-card-labels recovery.
          HELP
          REMOVE_HELP = <<~HELP + COMMON_HELP
            usage: planka remove label LABEL --card CARD [--board BOARD] [-o human|json]
            Remove only this association; an absent association is a no-op. Preserve the label and card.
            JSON uses data/meta/error with cardId, labelId, and present; meta.changed is true/false/null.
            A lost/malformed write response gives readback-card-labels recovery.
          HELP

          def self.prepare_add(env, instance:, flags:)
            Cards.prepare_scope(env, instance: instance, flags: flags).merge(present: true)
          end

          def self.prepare_remove(env, instance:, flags:)
            Cards.prepare_scope(env, instance: instance, flags: flags).merge(present: false)
          end

          def self.format(data) = "Label #{data['labelId']} on card #{data['cardId']}\npresent: #{data['present']}"

          GROUP_HELP = {
            "add" => "  label LABEL --card CARD  Add one existing board label to a card\n",
            "remove" => "  label LABEL --card CARD  Detach only this label from a card\n",
          }.freeze

          COMMANDS = {
            ["remove", "label"] => Command.new(aliases: [["remove", "labels"]], names: true, mutation: true,
              resource: "label", collection: "labels", flags: { "--card CARD" => :card, "--board BOARD" => :board },
              validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare_remove),
              help: REMOVE_HELP, reader: Planka::Cards::Labels, formatter: method(:format)),
            ["add", "label"] => Command.new(aliases: [["add", "labels"]], names: true, mutation: true,
              resource: "label", collection: "labels", flags: { "--card CARD" => :card, "--board BOARD" => :board },
              validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare_add),
              help: ADD_HELP, reader: Planka::Cards::Labels, formatter: method(:format)),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
