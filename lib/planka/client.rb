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
      @token = request(:post, "/api/access-tokens", emailOrUsername: email, password: password).fetch("item")
    end

    def sign_out
      request(:delete, "/api/access-tokens/me") if @token
    rescue Error
      nil
    end

    def board(id) = request(:get, "/api/boards/#{id}").fetch("included")

    def comments(card_id) = request(:get, "/api/cards/#{card_id}/comments").fetch("items")

    def card(id) = request(:get, "/api/cards/#{id}")

    def create_task_list(card_id, **attrs) = request(:post, "/api/cards/#{card_id}/task-lists", attrs).fetch("item")

    def create_task(task_list_id, **attrs) = request(:post, "/api/task-lists/#{task_list_id}/tasks", attrs).fetch("item")

    def me = request(:get, "/api/users/me").fetch("item")

    # Every board the signed-in user can see, across projects.
    def board_ids = request(:get, "/api/projects").dig("included", "boards").map { |board| board["id"] }

    def add_card_member(card_id, user_id) = request(:post, "/api/cards/#{card_id}/card-memberships", userId: user_id)

    def move_card(card_id, list_id, position: 65_535) = request(:patch, "/api/cards/#{card_id}", listId: list_id, position:)

    def comment(card_id, text) = request(:post, "/api/cards/#{card_id}/comments", text:)

    ServerError = Class.new(Error)

    # Planka and its proxy fail now and then with a 5xx or a dropped
    # connection, so a request gets three tries, one and then two seconds apart.
    ATTEMPTS = 3
    TRANSIENT = [ ServerError, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, EOFError, SocketError ].freeze

    def request(method, path, body = nil)
      attempt = 0
      begin
        attempt += 1
        send_request(method, path, body)
      rescue *TRANSIENT => e
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
      raise Error, "#{method.upcase} #{path}: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end
  end
end
