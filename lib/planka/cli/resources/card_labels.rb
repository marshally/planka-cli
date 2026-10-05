require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module CardLabels
        COMMANDS = %w[add remove].to_h do |verb|
          [[verb, "label"], Command.new(names: true, mutation: true, required_flags: [:card], resource: "label", collection: "labels", reader: Planka::Cards::Labels,
            flags: { "--card CARD" => :card },
            validate_flags: ->(flags) { "Exactly one --card required" if flags[:card] && flags[:card].size != 1 },
            prepare: ->(_env, instance:, flags:) { { card: instance.resolve(flags.fetch(:card).first, resource: "card", collection: "cards"), present: verb == "add" } },
            help: "usage: planka #{verb} label LABEL --card CARD [-o human|json]\nExact board label name or ID. Requires connection credentials; no default board. Idempotent; preserves other labels. JSON data: cardId, labelId, present; meta.changed. Lost response requires readback-card-labels, never blind retry.",
            formatter: ->(data) { "Card #{data['cardId']}: label #{data['labelId']} present=#{data['present']}" })]
        end.freeze
        def self.commands = COMMANDS
        def self.groups = { "add" => "add label LABEL --card CARD", "remove" => "remove label LABEL --card CARD" }
        def self.root_help = "  add/remove label LABEL --card CARD  Set one card-label relationship\n"
      end
    end
  end
end
