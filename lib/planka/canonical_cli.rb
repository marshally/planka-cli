require "optparse"

module Planka
  # The canonical adapter owns routing/output; legacy leaf parsers stay intact.
  module CanonicalCLI
    module_function

    ROOT_HELP = <<~HELP
      usage: planka <verb> <resource> [reference] [flags]
      Administration:
        describe card CARD  Read card details and related data (read-only)
        describe board BOARD  Read board snapshot and related data (read-only)
      Legacy commands (deprecated, retained indefinitely):
    HELP
    GROUP_HELP = <<~HELP
      usage: planka describe <resource> REF [flags]
        card CARD  Read card details and related data (read-only)
        board BOARD  Read board snapshot and related data (read-only)
    HELP
    LEAF_HELP = <<~HELP
      usage: planka describe card CARD [--output human|json]
      Read-only: card ID or same-instance card URL; no board setting required.
      Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
      Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
      Example: planka describe card 123 -o json
    HELP

    BOARD_HELP = <<~HELP
      usage: planka describe board BOARD [--output human|json]
      Read-only: board ID or same-instance board URL; an explicit target is required.
      Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
      Human output matches snapshot. JSON uses data/meta/error; failures exit 1 or 2.
      Example: planka describe board 123 -o json
    HELP

    RESOURCES = {
      "card" => { collection: "cards", help: LEAF_HELP, read: :card_description }.freeze,
      "board" => { collection: "boards", help: BOARD_HELP, read: :board_description }.freeze,
    }.freeze

    def root_help(commands)
      [ROOT_HELP, "commands: #{commands.join(', ')}", "\nRun planka <command> --help for command usage and options."].join("\n")
    end

    def run(args, legacy_commands:)
      requested_output = args.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
      requested_output = "json" if args.include?("--output=json") || args.include?("-ojson")
      options = { output: requested_output == "json" ? "json" : "human", program: args.include?("describe") ? "planka describe" : "planka" }
      parser = OptionParser.new do |o|
        o.on("-o", "--output FORMAT", %w[human json]) do |v|
          if options[:seen_output] && options[:seen_output] != v
            fail_command(options, "invalid_input", "Conflicting output formats", 2)
          end
          options[:seen_output] = options[:output] = v
        end
        o.on("-h", "--help") { options[:help] = true }
      end
      parser.parse!(args)
      resource_name = args[1].to_s.delete_suffix("s")
      resource = RESOURCES[resource_name]
      unless args.empty? || (args.first == "describe" && (args.size == 1 || resource))
        fail_command(options, "invalid_input", "unknown command; see planka --help", 2)
      end
      options[:program] = "planka describe #{resource_name}" if resource
      if args.size > 3
        fail_command(options, "invalid_input", "Unexpected arguments; see planka describe --help", 2)
      end
      if options[:help]
        help = if args.empty?
          root_help(legacy_commands)
        elsif args.size == 1
          GROUP_HELP
        else
          resource.fetch(:help)
        end
        puts help
        puts parser.help
        return
      end
      unless resource && args.size == 3
        fail_command(options, "invalid_input", "Expected planka describe RESOURCE REF; see planka describe --help", 2)
      end
      collection = resource.fetch(:collection)
      unless args.last.match?(/\A\d+\z/) || args.last.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/#{collection}/\d+/?\z})
        fail_command(options, "invalid_input", "Expected a numeric #{resource_name} ID or supported #{resource_name} URL", 2)
      end
      missing = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].select { |key| ENV[key].to_s.strip.empty? }
      fail_command(options, "configuration_error", "Missing required environment: #{missing.join(', ')}", 1) unless missing.empty?
      base = URI(ENV.fetch("PLANKA_BASE_URL"))
      unless %w[http https].include?(base.scheme) && base.host && !base.userinfo && !base.query && !base.fragment
        fail_command(options, "configuration_error", "PLANKA_BASE_URL must be an HTTP(S) instance URL without credentials, query, or fragment", 1)
      end
      unless args.last.match?(/\A\d+\z/)
        begin
          reference = URI(args.last)
        rescue URI::InvalidURIError
          fail_command(options, "invalid_input", "Invalid #{resource_name} URL; use a numeric #{resource_name} ID or same-instance #{resource_name} URL", 2)
        end
        unless [reference.scheme, reference.host, reference.port] == [base.scheme, base.host, base.port] &&
            reference.path.match?(%r{\A#{Regexp.escape(base.path.sub(%r{/+\z}, ''))}/#{collection}/\d+/?\z}) && !reference.userinfo && !reference.query && !reference.fragment
          fail_command(options, "invalid_input", "#{resource_name.capitalize} URL must belong to PLANKA_BASE_URL", 2)
        end
      end
      cleanup_notice = ->(_error) { warn "#{options[:program]}: session cleanup failed; the read result is unchanged" }
      Planka::Client.session(on_cleanup_error: cleanup_notice) do |client|
        id = args.last[/(\d+)\/?\z/, 1]
        detail, human = public_send(resource.fetch(:read), client, id)
        Planka::CLI.emit({ "data" => detail, "meta" => {}, "error" => nil },
          output: options[:output], human: human)
      end
    rescue Planka::Client::HTTPError => e
      code = { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found" }.fetch(e.status, "api_error")
      fail_command(options, code, "API request failed (HTTP #{e.status}); verify the resource and access permissions", 1)
    rescue Planka::Error, KeyError, JSON::ParserError, TypeError, NoMethodError
      fail_command(options, "api_error", "Could not read complete resource details; verify server availability and API compatibility", 1)
    rescue SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError
      fail_command(options, "network_error", "Could not reach Planka; check the instance URL and network", 1)
    rescue URI::InvalidURIError
      fail_command(options, "configuration_error", "Invalid PLANKA_BASE_URL", 1)
    rescue OptionParser::ParseError
      fail_command(options, "invalid_input", "Invalid option or output format; see planka describe --help", 2)
    end

    def card_description(client, id)
      detail = Planka::CardDetail.new(client).for(id)
      [detail, Planka::CLI.card_detail(detail)]
    end

    def board_description(client, id)
      included = client.board(id)
      unless included.is_a?(Hash) && Planka::Snapshot::RECORD_TYPES.all? { |key|
        records = included.fetch(key, [])
        records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) }
      }
        raise Planka::Error, "Invalid board snapshot payload"
      end
      detail = { "boardId" => id }.merge(Planka::Snapshot.new(included).to_h)
      [detail, Planka::CLI.board_snapshot(detail)]
    end

    def fail_command(options, code, message, status)
      warn "#{options[:program]}: #{message}"
      if options[:output] == "json"
        puts JSON.generate({ "data" => nil, "meta" => {}, "error" => { "code" => code, "message" => message } })
      end
      exit status
    end

  end
end
