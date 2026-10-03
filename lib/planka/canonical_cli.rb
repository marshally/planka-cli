require "optparse"

module Planka
  # The canonical adapter owns routing/output; legacy leaf parsers stay intact.
  module CanonicalCLI
    module_function

    ROOT_HELP = <<~HELP
      usage: planka <verb> <resource> [reference] [flags]
      Administration:
        describe card CARD  Read card details and related data (read-only)
      Legacy commands (deprecated, retained indefinitely):
    HELP
    GROUP_HELP = <<~HELP
      usage: planka describe <resource> REF [flags]
        card CARD  Read card details and related data (read-only)
    HELP
    LEAF_HELP = <<~HELP
      usage: planka describe card CARD [--output human|json]
      Read-only: card ID or same-instance card URL; no board setting required.
      Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
      Defaults to human output. JSON uses data/meta/error; failures exit 1 or 2.
      Example: planka describe card 123 -o json
    HELP

    def root_help(commands)
      [ROOT_HELP, "commands: #{commands.join(', ')}", "\nRun planka <command> --help for command usage and options."].join("\n")
    end

    def run(args, legacy_commands:)
      requested_output = args.each_cons(2).filter_map { |flag, value| value if %w[-o --output].include?(flag) }.last
      requested_output = "json" if args.include?("--output=json") || args.include?("-ojson")
      options = { output: requested_output == "json" ? "json" : "human", program: args.include?("describe") ? "planka describe card" : "planka" }
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
      unless [[], ["describe"], ["describe", "card"], ["describe", "cards"]].include?(args.first(2))
        fail_command(options, "invalid_input", "unknown command; see planka --help", 2)
      end
      if args.size > 3
        fail_command(options, "invalid_input", "Unexpected arguments; see planka describe card --help", 2)
      end
      if options[:help]
        puts [root_help(legacy_commands), GROUP_HELP, LEAF_HELP][[args.length, 2].min]
        puts parser.help
        return
      end
      unless args.first == "describe" && %w[card cards].include?(args[1]) && args.size == 3
        fail_command(options, "invalid_input", "Expected planka describe card CARD; see planka describe --help", 2)
      end
      unless args.last.match?(/\A\d+\z/) || args.last.match?(%r{\Ahttps?://[^/]+(?:/[^/?#]+)*/cards/\d+/?\z})
        fail_command(options, "invalid_input", "Expected a numeric card ID or supported card URL", 2)
      end
      missing = %w[PLANKA_BASE_URL PLANKA_AGENT_EMAIL PLANKA_AGENT_PASSWORD].select { |key| ENV[key].to_s.strip.empty? }
      fail_command(options, "configuration_error", "Missing required environment: #{missing.join(', ')}", 1) unless missing.empty?
      base = URI(ENV.fetch("PLANKA_BASE_URL"))
      unless %w[http https].include?(base.scheme) && base.host && !base.userinfo && !base.query && !base.fragment
        fail_command(options, "configuration_error", "PLANKA_BASE_URL must be an HTTP(S) instance URL without credentials, query, or fragment", 1)
      end
      unless args.last.match?(/\A\d+\z/)
        reference = URI(args.last)
        unless [reference.scheme, reference.host, reference.port] == [base.scheme, base.host, base.port] &&
            reference.path.match?(%r{\A#{Regexp.escape(base.path.sub(%r{/+\z}, ''))}/cards/\d+/?\z}) && !reference.userinfo && !reference.query && !reference.fragment
          fail_command(options, "invalid_input", "Card URL must belong to PLANKA_BASE_URL", 2)
        end
      end
      with_session do |client|
        detail = Planka::CardDetail.new(client).for(Planka.card_id(args.last))
        Planka::CLI.emit({ "data" => detail, "meta" => {}, "error" => nil },
          output: options[:output], human: Planka::CLI.card_detail(detail))
      end
    rescue Planka::Client::HTTPError => e
      code = { 401 => "authentication_error", 403 => "authorization_error", 404 => "not_found" }.fetch(e.status, "api_error")
      fail_command(options, code, "API request failed (HTTP #{e.status}); verify the card and access permissions", 1)
    rescue Planka::Error, KeyError, JSON::ParserError
      fail_command(options, "api_error", "Could not read complete card details; verify server availability and API compatibility", 1)
    rescue SystemCallError, SocketError, Timeout::Error, EOFError, IOError
      fail_command(options, "network_error", "Could not reach Planka; check the instance URL and network", 1)
    rescue URI::InvalidURIError
      fail_command(options, "configuration_error", "Invalid PLANKA_BASE_URL", 1)
    rescue OptionParser::ParseError
      fail_command(options, "invalid_input", "Invalid option or output format; see planka describe card --help", 2)
    end

    def with_session
      client = Planka::Client.new(ENV.fetch("PLANKA_BASE_URL"))
      client.sign_in(ENV.fetch("PLANKA_AGENT_EMAIL"), ENV.fetch("PLANKA_AGENT_PASSWORD"))
      yield client
    ensure
      begin
        client&.sign_out(suppress_errors: false)
      rescue Planka::Error, SystemCallError, SocketError, Timeout::Error, EOFError, IOError, JSON::ParserError
        warn "planka describe card: session cleanup failed; the read result is unchanged"
      end
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
