require 'planka'
require 'planka/cli/command'
require 'planka/cli/failure'
module Planka
  module CLI
    module Resources
      module Cards
        module Tasks
          HELP = <<~HELP
            usage: planka update task TASK --card CARD --completed|--no-completed [-o human|json]
            TASK is an ID or exact name within the card. Ambiguous names report IDs.
            CARD is a numeric ID or same-instance card URL. No default board required.
            Requires connection credentials. Sets only completion; already satisfied is a no-op.
            Linked tasks are refused; blocker completion belongs to Planka.
            JSON data: id,name,taskListId,cardId,isCompleted; meta.changed true/false/null.
            Lost/malformed write response requires readback-task; do not blindly retry.
          HELP
          def self.prepare(_env, instance:, flags:)
            raise Failure.new(code: 'invalid_input', status: 2, message: 'Exactly one --card is required') unless flags[:card]
            raise Failure.new(code: 'invalid_input', status: 2, message: 'Exactly one --completed or --no-completed is required') unless flags[:completed]
            { card: instance.resolve(flags.fetch(:card).first, resource: 'card', collection: 'cards'), completed: flags.fetch(:completed).first }
          end

          COMMANDS = {
            ['update', 'task'] => Command.new(names: true, mutation: true, resource: 'task', collection: 'tasks', reader: Planka::Cards::Tasks,
              flags: { '--card CARD' => :card, '--[no-]completed' => :completed },
              validate_flags: ->(flags) { 'Exactly one --card and one completion flag required' if (flags[:card] && flags[:card].size != 1) || (flags[:completed] && flags[:completed].size != 1) },
              prepare: method(:prepare),
              help: HELP, formatter: ->(data) { "Task #{data['id']}: completed=#{data['isCompleted']}" })
          }.freeze
          def self.commands = COMMANDS
          def self.groups = { 'update' => HELP }
          def self.root_help = "  update task TASK --card CARD --[no-]completed  Set ordinary task completion\n"
        end
      end
    end
  end
end
