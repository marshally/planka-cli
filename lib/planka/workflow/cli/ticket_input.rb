require "json"
require "planka/cli/failure"
require "planka/cli/input_file"

module Planka
  module Workflow
    module CLI
      # Prepares the complete operation input for resuming a ticket.
      module TicketInput
        def self.resume(_env, instance:, flags:, **)
          unless flags[:criteria_file]
            raise Planka::CLI::Failure.invalid_input("resume ticket requires --criteria-file")
          end

          { base_url: instance.base_url, criteria: criteria(flags.fetch(:criteria_file).first) }
        end

        # Prepares every value needed by ticket creation before authentication.
        def self.creation(env, instance:, flags:, **)
          unless flags[:list] && flags[:name] && flags[:criteria_file]
            raise Planka::CLI::Failure.invalid_input("create ticket requires --list, --name, and --criteria-file")
          end
          if flags[:criteria_file].first == "-" && flags.dig(:description_file, 0) == "-"
            raise Planka::CLI::Failure.invalid_input("--criteria-file and --description-file cannot both read stdin")
          end

          Planka::CLI::CardInput.creation(env, instance: instance, flags: flags)
                                .merge(base_url: instance.base_url, criteria: criteria(flags.fetch(:criteria_file).first))
        end

        # A nonempty JSON array of distinct criteria, each a valid task name.
        def self.criteria(path)
          criteria = JSON.parse(Planka::CLI::InputFile.read(path))
          return criteria.map { |criterion| criterion.freeze }.freeze if criteria.is_a?(Array) && !criteria.empty? && criteria.uniq.size == criteria.size &&
                                                                         criteria.all? { |criterion| Planka::Records.text?(criterion, Criteria::Fill::CRITERION_LIMIT) && !criterion.strip.empty? }

          invalid_criteria!("--criteria-file must be a nonempty JSON array of distinct nonblank strings " \
                            "of at most #{Criteria::Fill::CRITERION_LIMIT} characters")
        rescue JSON::ParserError
          invalid_criteria!("--criteria-file must contain a JSON array")
        rescue SystemCallError, IOError
          invalid_criteria!("Could not read --criteria-file")
        end

        def self.invalid_criteria!(message) = raise(Planka::CLI::Failure.invalid_input(message))
        private_class_method :criteria, :invalid_criteria!
      end
    end
  end
end
