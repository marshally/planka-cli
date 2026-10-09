require "planka/workflow/format"
require "planka/workflow/configuration"
require "planka/cli/failure"
require "planka/cli/command"
require "planka/cli/input_file"
require "planka/cli/card_input"
require "planka/cli/resources/scalar_flags"
require "json"

module Planka
  module Workflow
    # The single attachment point between workflow commands and shared CLI plumbing.
    module CLI
      ROOT_HELP = <<~HELP
        Workflows:
          workflow create spec --list LIST --name NAME  Publish a project spec without acceptance criteria
          workflow claim CARD  Add your membership and move the card to in-progress
          workflow resume ticket CARD --criteria-file FILE  Add missing acceptance criteria to a ticket
          workflow guide  Read built-in agent guidance (offline)
          workflow next  Select queued work without claiming (read-only)
          workflow pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          workflow branch-name CARD  Read the card's branch name (read-only)
          workflow claim-status  Inspect claims across all accessible boards (read-only)
      HELP
      GROUP_HELP = <<~HELP
        usage: planka workflow <operation> [arguments] [flags]
          create spec --list LIST --name NAME  Publish a project spec without acceptance criteria
          claim CARD  Add your membership and move the card to in-progress
          resume ticket CARD --criteria-file FILE  Add missing acceptance criteria to a ticket
          guide  Read built-in agent guidance (offline)
          next  Select queued work without claiming (read-only)
          pending-criteria CARD  Read unfinished acceptance criteria (read-only)
          branch-name CARD  Read the card's branch name (read-only)
          claim-status  Inspect claims across all accessible boards (read-only)
      HELP
      GUIDE_HELP = <<~HELP
        usage: planka workflow guide [--output human|json]
        Offline: no credentials or network access, even when connection settings are supplied.
        Takes no target or scope flags. Human output is the built-in agent guide.
        JSON uses data/meta/error; data has instructions. Invalid input exits 2.
        Example: planka workflow guide -o json
      HELP
      NEXT_HELP = <<~HELP
        usage: planka workflow next [--board BOARD] [--label LABEL] [--output human|json]
        read-only: selects work from ready-for-agent; does not claim or change resources.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        --board accepts a numeric ID or same-instance board URL; otherwise PLANKA_BOARD_ID is required.
        No mode label: priority by position. feature:SLUG: tickets by creation order.
        effort:SLUG: wayfinder:map and takeable frontier by position.
        Repeated --label values AND-match exactly before selection, including specs/maps.
        At most one distinct feature: or effort: mode label; other labels narrow the queue.
        Completed linked tasks retain blocker handoff/stacking metadata; unfinished ones prevent selection.
        Cards labelled quarantine are never selected; waiting reports mark them quarantined.
        gh must be installed for blocker PR lookup, with authentication for private repositories.
        Unknown/failed PR lookups preserve the recorded branch and an unknown state; malformed results fail.
        No handoff or multiple unmerged blockers yield AMBIGUOUS; an empty queue succeeds.
        Human output matches next-card. JSON uses data/meta/error and the pick, waiting, or frontier schema.
        No --limit, mutation, or collection completeness claim. Failures exit 1 or 2.
        Example: planka workflow next --board 123 --label feature:search -o json
      HELP
      CLAIM_STATUS_HELP = <<~HELP
        usage: planka workflow claim-status [--output human|json]
        Read-only: inspects the signed-in user's claims across all accessible boards.
        Returns the first open claimed card without a PR handoff, or free.
        Cards labelled quarantine never hold the claim; legacy loop-lock still reports them.
        This does not acquire a lock and makes no GitHub requests.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        No target or board setting is required; PLANKA_BOARD_ID does not restrict scope.
        Human output matches loop-lock; JSON data has held and card, plus claimedAt and ageSeconds when held.
        Failures exit 1 or 2. Example: planka workflow claim-status -o json
      HELP
      BRANCH_NAME_HELP = <<~HELP
        usage: planka workflow branch-name CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Uses the existing feature-label, title-slug, and length rules of branch-name.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        PLANKA_BRANCH_PREFIX optionally reserves room within the 63-character limit.
        Human output is the branch name; JSON data has cardId and branch.
        Failures exit 1 or 2. Example: planka workflow branch-name 123 -o json
      HELP
      PENDING_CRITERIA_HELP = <<~HELP
        usage: planka workflow pending-criteria CARD [--output human|json]
        Read-only: card ID or same-instance card URL; no board setting required.
        Prints unfinished tasks from lists named exactly "Acceptance criteria", in board-response order.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        JSON data has cardId and criteria; empty criteria are a successful empty array.
        Human output is one criterion per line. Failures exit 1 or 2.
        Example: planka workflow pending-criteria 123 -o json
      HELP

      CLAIM_HELP = <<~HELP
        usage: planka workflow claim CARD [--output human|json]
        Adds the signed-in user's membership, then moves the card to its board's unique in-progress list.
        CARD is a numeric ID or same-instance card URL; no board setting required.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Existing membership is retained. Already in-progress cards keep their position; satisfied claims are no-ops.
        JSON uses data/meta/error: card, userId, inProgressListId, claimed, memberAdded, moved; meta.changed reports effects.
        Failures preserve known effects and provide readback-claim recovery; uncertain steps are null.
        Inspect with planka describe card CARD -o json before retrying. This is not an atomic or exclusive lock.
        Exit 0: success; 2: local input; 1: configuration, API, partial or unknown outcome.
        Example: planka workflow claim 123 -o json
      HELP

      RESUME_GROUP_HELP = <<~HELP
        usage: planka workflow resume <resource> REF [flags]
          ticket CARD --criteria-file FILE  Add missing acceptance criteria to a ticket
      HELP

      CREATE_SPEC_HELP = <<~HELP
        usage: planka workflow create spec --list LIST [--board BOARD] --name NAME [--description-file FILE|-]
                                           [--position N] [--output human|json]
        Creates a project card without an Acceptance criteria list. Appends unless positioned.
        LIST is an ID, same-instance URL, or exact name with --board BOARD or PLANKA_BOARD_ID.
        BOARD is an ID or same-instance URL; an explicit board asserts the list's parent.
        A list ID/URL ignores PLANKA_BOARD_ID. Archive/trash lists require --board and reject --position.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        spec/specs are aliases. No positional target or criteria flag is accepted.
        NAME is nonempty, at most 1024 UTF-16 units; FILE (- for stdin) must be nonempty UTF-8 text,
        at most 1048576 UTF-16 units. Text is preserved and read before any request.
        --position is finite and nonnegative where supported; omitted descriptions stay null.
        JSON data: id, name, description, type, boardId, listId, position, createdAt, updatedAt.
        meta.changed: true on confirmation, false on rejection, null when the write is unknown.
        A valid new returned ID is preserved even when other response fields are invalid.
        Recovery: readback-card for a known ID, otherwise readback-cards for the list. Never retry blindly.
        Inspect with planka get card CARD -o json, or get cards --list LIST -o json for active/closed lists.
        Archive/trash lists need inspection in Planka when the created ID is unknown.
        Exit 0: success; 2: local input; 1: configuration, lookup, API or unknown outcome.
        Example: planka workflow create spec --list 123 --name Search --description-file spec.md -o json
      HELP

      CREATE_GROUP_HELP = <<~HELP
        usage: planka workflow create <resource> [flags]
          spec --list LIST --name NAME  Publish a project spec without acceptance criteria
      HELP
      RESUME_TICKET_HELP = <<~HELP
        usage: planka workflow resume ticket CARD --criteria-file FILE|- [--output human|json]
        Finishes an existing ticket: adds criteria missing from its "Acceptance criteria" task list. Never creates a card.
        CARD is a numeric ID or same-instance card URL; no board setting required. ticket/tickets are aliases.
        FILE (- for stdin) is a nonempty JSON array of distinct criteria: nonblank strings of at most 1024 characters.
        It is read and validated before any request; missing connection settings are reported first.
        Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
        Reuses the card's one criteria list, creating it when absent; two or more such lists fail before writes.
        Criteria already present by exact text are kept with their completion and order; missing ones are appended
        in FILE order. Other tasks are never changed or deleted. All criteria present is a no-op (meta.changed false).
        JSON data: card {id, name, url}, taskList {id, name, created}, tasks [{id, name, isCompleted, created}].
        Failures keep known IDs; uncertain steps are null. Recovery is resume-ticket for the card (and task list):
        inspect with planka describe card CARD -o json, then rerun this command; it adds only what is still missing.
        Exit 0: success; 2: local input; 1: configuration, API, partial or unknown outcome.
        Example: planka workflow resume ticket 123 --criteria-file criteria.json -o json
      HELP

      def self.branch_preparation(env, instance:, **)
        { base_url: instance.base_url, prefix: Configuration.from_env(env).branch_prefix }
      rescue ConfigurationError => error
        raise Planka::CLI::Failure.configuration(error.message)
      end

      def self.next_preparation(env, instance:, flags:, **)
        board = flags.fetch(:board, []).first || env["PLANKA_BOARD_ID"]
        if board.to_s.strip.empty?
          raise Planka::CLI::Failure.configuration("Missing required environment: PLANKA_BOARD_ID (or supply --board BOARD)")
        end

        { base_url: instance.base_url, board_id: instance.resolve(board, resource: "board", collection: "boards"), labels: flags.fetch(:labels, []).uniq }
      rescue Planka::CLI::Instance::InvalidReference => error
        if flags.fetch(:board, []).empty?
          raise Planka::CLI::Failure.configuration("PLANKA_BOARD_ID must be a numeric board ID or same-instance board URL")
        end

        raise Planka::CLI::Failure.invalid_input(error.message)
      end

      def self.resume_preparation(_env, instance:, flags:, **)
        unless flags[:criteria_file]
          raise Planka::CLI::Failure.invalid_input("resume ticket requires --criteria-file")
        end

        { base_url: instance.base_url, criteria: criteria(flags.fetch(:criteria_file).first) }
      end

      def self.spec_preparation(env, instance:, flags:, **)
        unless flags[:list] && flags[:name]
          raise Planka::CLI::Failure.invalid_input("create spec requires --list and --name")
        end

        Planka::CLI::CardInput.creation(env, instance: instance, flags: flags)
      end

      # A nonempty JSON array of distinct criteria, each a valid task name.
      def self.criteria(path)
        criteria = JSON.parse(Planka::CLI::InputFile.read(path))
        return criteria if criteria.is_a?(Array) && !criteria.empty? && criteria.uniq.size == criteria.size &&
                           criteria.all? { |criterion| Records.text?(criterion, Resume::Ticket::CRITERION_LIMIT) && !criterion.strip.empty? }

        invalid_criteria!("--criteria-file must be a nonempty JSON array of distinct nonblank strings " \
                          "of at most #{Resume::Ticket::CRITERION_LIMIT} characters")
      rescue JSON::ParserError
        invalid_criteria!("--criteria-file must contain a JSON array")
      rescue SystemCallError, IOError
        invalid_criteria!("Could not read --criteria-file")
      end

      def self.invalid_criteria!(message) = raise(Planka::CLI::Failure.invalid_input(message))
      private_class_method :criteria, :invalid_criteria!

      def self.validate_next_flags(flags)
        boards = flags.fetch(:board, [])
        labels = flags.fetch(:labels, []).uniq
        if boards.uniq.size > 1 || boards.any? { |value| value.strip.empty? } || labels.any? { |value| value.strip.empty? } ||
           labels.count { |label| label.start_with?("feature:", "effort:") } > 1
          "Use one board and at most one feature: or effort: mode label; labels must be nonempty"
        end
      end

      COMMANDS = {
        ["workflow", "create", "spec"] => Planka::CLI::Command.new(aliases: [["workflow", "create", "specs"]], reference: false, mutation: true, resource: "card", collection: "cards",
                                                                   flags: { "--list LIST" => :list, "--board BOARD" => :board, "--name NAME" => :name,
                                                                            "--description-file FILE" => :description_file, "--position N" => :position },
                                                                   validate_flags: Planka::CLI::CardInput.method(:error), prepare: method(:spec_preparation),
                                                                   help: CREATE_SPEC_HELP, operation: Create::Spec.method(:create), formatter: Format.method(:created_spec)),
        ["workflow", "claim"] => Planka::CLI::Command.new(resource: "card", collection: "cards", mutation: true, help: CLAIM_HELP, operation: Claim::Card.method(:read), formatter: Format.method(:claim)),
        ["workflow", "resume", "ticket"] => Planka::CLI::Command.new(aliases: [["workflow", "resume", "tickets"]], resource: "card", collection: "cards", mutation: true,
                                                                     flags: { "--criteria-file FILE" => :criteria_file },
                                                                     validate_flags: Planka::CLI::Resources::ScalarFlags.method(:error),
                                                                     prepare: method(:resume_preparation), help: RESUME_TICKET_HELP,
                                                                     operation: Resume::Ticket.method(:read), formatter: Format.method(:resumed_ticket)),
        ["workflow", "next"] => Planka::CLI::Command.new(reference: false, resource: "board", collection: "boards", flags: { "--board BOARD" => :board, "--label LABEL" => :labels }, validate_flags: method(:validate_next_flags), prepare: method(:next_preparation), help: NEXT_HELP, operation: NextSelection.method(:read), projector: :as_json.to_proc, formatter: Format.method(:next_selection)),
        ["workflow", "guide"] => Planka::CLI::Command.new(reference: false, session: false, help: GUIDE_HELP, operation: Guide.method(:read), formatter: Format.method(:guide)),
        ["workflow", "claim-status"] => Planka::CLI::Command.new(resource: "card", collection: "cards", reference: false, help: CLAIM_STATUS_HELP, operation: ClaimStatus.method(:read), formatter: Format.method(:loop_lock)),
        ["workflow", "pending-criteria"] => Planka::CLI::Command.new(resource: "card", collection: "cards", help: PENDING_CRITERIA_HELP, operation: PendingCriteria.method(:read), formatter: Format.method(:pending_criteria)),
        ["workflow", "branch-name"] => Planka::CLI::Command.new(resource: "card", collection: "cards", help: BRANCH_NAME_HELP, operation: BranchName.method(:read), formatter: Format.method(:branch_name), prepare: method(:branch_preparation)),
      }.freeze
      def self.commands = COMMANDS
      def self.groups = { ["workflow"] => GROUP_HELP, ["workflow", "resume"] => RESUME_GROUP_HELP, ["workflow", "create"] => CREATE_GROUP_HELP }
      def self.root_help = ROOT_HELP
    end
  end
end
