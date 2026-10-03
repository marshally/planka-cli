require "json"
require "net/http"
require "uri"

module Planka
  # A signed-in session against Planka's REST API as the board's bot user.
  class Client
    def self.session
      client = new(ENV.fetch("PLANKA_BASE_URL"))
      client.sign_in(ENV.fetch("PLANKA_AGENT_EMAIL"), ENV.fetch("PLANKA_AGENT_PASSWORD"))
      yield client
    ensure
      client&.sign_out
    end

    def initialize(base_url)
      @base = URI(base_url)
      @token = nil
    end

    def sign_in(email, password)
      @token = request(:post, "/api/access-tokens", { emailOrUsername: email, password: password }).fetch("item")
    end

    def sign_out(suppress_errors: true)
      request(:delete, "/api/access-tokens/me") if @token
    rescue Error
      raise unless suppress_errors

      nil
    end

    def board(id) = request(:get, "/api/boards/#{id}").fetch("included")

    def comments(card_id) = request(:get, "/api/cards/#{card_id}/comments").fetch("items")

    def card(id) = request(:get, "/api/cards/#{id}")

    # Cards in a list, newest-position last, as GET returns them.
    def list_cards(list_id) = request(:get, "/api/lists/#{list_id}/cards")

    # Creates return the new record under "item". A create is not idempotent:
    # a retry after an unknown outcome would make a second copy, so these pass
    # idempotent: false and leave reconciliation to a read-back.
    def create_card(list_id, **attrs) = request(:post, "/api/lists/#{list_id}/cards", attrs, idempotent: false).fetch("item")

    def update_card(card_id, **attrs) = request(:patch, "/api/cards/#{card_id}", attrs).fetch("item")

    def create_list(board_id, **attrs) = request(:post, "/api/boards/#{board_id}/lists", attrs, idempotent: false).fetch("item")

    def create_label(board_id, **attrs) = request(:post, "/api/boards/#{board_id}/labels", attrs, idempotent: false).fetch("item")

    def add_card_label(card_id, label_id) = request(:post, "/api/cards/#{card_id}/card-labels", { labelId: label_id }, idempotent: false)

    def create_task_list(card_id, **attrs) = request(:post, "/api/cards/#{card_id}/task-lists", attrs, idempotent: false).fetch("item")

    def update_task_list(task_list_id, **attrs) = request(:patch, "/api/task-lists/#{task_list_id}", attrs).fetch("item")

    def create_task(task_list_id, **attrs) = request(:post, "/api/task-lists/#{task_list_id}/tasks", attrs, idempotent: false).fetch("item")

    def me = request(:get, "/api/users/me").fetch("item")

    # Every board the signed-in user can see, across projects.
    def board_ids = request(:get, "/api/projects").dig("included", "boards").map { |board| board["id"] }

    def add_card_member(card_id, user_id) = request(:post, "/api/cards/#{card_id}/card-memberships", { userId: user_id }, idempotent: false)

    def move_card(card_id, list_id, position: 65_535) = request(:patch, "/api/cards/#{card_id}", { listId: list_id, position: }).fetch("item")

    def comment(card_id, text) = request(:post, "/api/cards/#{card_id}/comments", { text: }, idempotent: false)

    class HTTPError < Error
      attr_reader :status

      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    ServerError = Class.new(Error)
    # A non-idempotent request failed after Planka may already have applied it.
    UnknownOutcome = Class.new(Error)

    # Planka and its proxy fail now and then with a 5xx or a dropped
    # connection, so a request gets three tries, one and then two seconds apart.
    ATTEMPTS = 3
    # Failures before the request reaches Planka cannot have changed anything,
    # so retrying is always safe, even for a create.
    UNSENT = [ Errno::ECONNREFUSED, Net::OpenTimeout, SocketError ].freeze
    # Failures after the request was sent leave the outcome unknown: Planka may
    # have applied the change. Retrying is safe only when the call is idempotent.
    UNKNOWN = [ ServerError, Errno::ECONNRESET, Net::ReadTimeout, EOFError ].freeze
    TRANSIENT = (UNSENT + UNKNOWN).freeze

    def request(method, path, body = nil, idempotent: true)
      attempt = 0
      begin
        attempt += 1
        send_request(method, path, body)
      rescue *TRANSIENT => e
        raise UnknownOutcome, "#{method.upcase} #{path}: #{e.class} (outcome unknown, reconcile by reading back)" if !idempotent && UNKNOWN.any? { |klass| e.is_a?(klass) }
        raise if attempt == ATTEMPTS

        warn "planka: #{method.upcase} #{path} failed (#{e.class}), retrying"
        sleep attempt
        retry
      end
    end

    private

    def send_request(method, path, body)
      http = Net::HTTP.new(@base.host, @base.port)
      http.use_ssl = @base.scheme == "https"
      req = Net::HTTP.const_get(method.capitalize).new(path)
      req["Authorization"] = "Bearer #{@token}" if @token
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      res = http.request(req)
      raise ServerError, "#{method.upcase} #{path}: #{res.code} #{res.body}" if res.is_a?(Net::HTTPServerError)
      raise HTTPError.new("#{method.upcase} #{path}: #{res.code} #{res.body}", res.code.to_i) unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end
  end
end
