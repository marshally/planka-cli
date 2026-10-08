require "json"
require "net/http"
require "uri"
require_relative "position"
require_relative "records"

module Planka
  # A signed-in session against Planka's REST API as the board's bot user.
  class Client
    def self.session(base_url: nil, email: nil, password: nil, validate_responses: false, on_cleanup_error: nil)
      client = new(base_url || ENV.fetch("PLANKA_BASE_URL"), validate_responses: validate_responses)
      client.sign_in(email || ENV.fetch("PLANKA_AGENT_EMAIL"), password || ENV.fetch("PLANKA_AGENT_PASSWORD"))
      yield client
    ensure
      begin
        client&.sign_out(suppress_errors: on_cleanup_error.nil?)
      rescue Error, JSON::ParserError, *NETWORK_ERRORS => e
        raise unless on_cleanup_error

        on_cleanup_error.call(e)
      end
    end

    def initialize(base_url, validate_responses: false)
      @validate_responses = validate_responses
      @base = URI(base_url)
      @token = nil
    end

    def sign_in(email, password)
      response = request(:post, "/api/access-tokens", { emailOrUsername: email, password: password })
      if @validate_responses && (!response.is_a?(Hash) || !response["item"].is_a?(String) || response["item"].empty?)
        raise InvalidResponse, "Invalid authentication response"
      end

      @token = response.fetch("item")
    end

    def sign_out(suppress_errors: true)
      request(:delete, "/api/access-tokens/me") if @token
    rescue Error
      raise unless suppress_errors

      nil
    end

    def board(id)
      response = request(:get, "/api/boards/#{id}")
      if @validate_responses && !response["included"].is_a?(Hash)
        raise InvalidResponse, "Invalid board response"
      end

      response.fetch("included")
    end

    # The board item with its included records; #board returns only the latter.
    def board_document(id)
      document = request(:get, "/api/boards/#{id}")
      raise InvalidResponse, "Invalid board response" if @validate_responses && !(document["item"].is_a?(Hash) && document["included"].is_a?(Hash))

      document
    end

    # A finite (active or closed) list; Planka answers 404 for archive and trash.
    def list(id)
      response = request(:get, "/api/lists/#{id}")
      raise InvalidResponse, "Invalid list response" if @validate_responses && !response["item"].is_a?(Hash)

      response.fetch("item")
    end

    # A task list with its tasks; Planka answers 404 when it is missing or not visible.
    def task_list(id)
      response = request(:get, "/api/task-lists/#{id}")
      raise InvalidResponse, "Invalid task list response" if @validate_responses && !response["item"].is_a?(Hash)

      response.fetch("item")
    end

    def comments(card_id)
      response = request(:get, "/api/cards/#{card_id}/comments")
      if @validate_responses && !response["items"].is_a?(Array)
        raise InvalidResponse, "Invalid comments response"
      end

      response.fetch("items")
    end

    def card(id) = request(:get, "/api/cards/#{id}")

    # Cards in a list, newest-position last, as GET returns them.
    def list_cards(list_id) = request(:get, "/api/lists/#{list_id}/cards")

    # Creates return the new record under "item".
    def create_card(list_id, **attrs) = item(request(:post, "/api/lists/#{list_id}/cards", attrs), "card")

    def update_card(card_id, **attrs) = item(request(:patch, "/api/cards/#{card_id}", attrs), "card")

    def delete_card(card_id) = item(request(:delete, "/api/cards/#{card_id}"), "card")

    def create_list(board_id, **attrs) = item(request(:post, "/api/boards/#{board_id}/lists", attrs), "list")

    def update_list(list_id, **attrs) = item(request(:patch, "/api/lists/#{list_id}", attrs), "list")

    def delete_list(list_id) = item(request(:delete, "/api/lists/#{list_id}"), "list")

    def create_label(board_id, **attrs) = request(:post, "/api/boards/#{board_id}/labels", attrs).fetch("item")

    def add_card_label(card_id, label_id) = request(:post, "/api/cards/#{card_id}/card-labels", { labelId: label_id })

    def remove_card_label(card_id, label_id) = request(:delete, "/api/cards/#{card_id}/card-labels/labelId:#{label_id}")

    def create_task_list(card_id, **attrs) = item(request(:post, "/api/cards/#{card_id}/task-lists", attrs), "task list")

    def update_task_list(task_list_id, **attrs) = item(request(:patch, "/api/task-lists/#{task_list_id}", attrs), "task list")

    def update_task(id, **attrs) = request(:patch, "/api/tasks/#{id}", attrs)["item"]

    def create_task(task_list_id, **attrs) = item(request(:post, "/api/task-lists/#{task_list_id}/tasks", attrs), "task")

    def me
      response = request(:get, "/api/users/me")
      raise InvalidResponse, "Invalid signed-in user response" if @validate_responses && !response["item"].is_a?(Hash)

      response.fetch("item")
    end

    # Every board the signed-in user can see, across projects.
    def board_ids
      document = request(:get, "/api/projects")
      if @validate_responses
        boards = document["included"].is_a?(Hash) && document["included"]["boards"]
        unless boards.is_a?(Array) && boards.all? { |board|
          board.is_a?(Hash) && Records.id?(board["id"])
        }
          raise InvalidResponse, "Invalid accessible board records"
        end
      end
      document.dig("included", "boards").map { |board| board["id"] }
    end

    def add_card_member(card_id, user_id) = request(:post, "/api/cards/#{card_id}/card-memberships", { userId: user_id })
    def remove_card_member(card_id, user_id) = request(:delete, "/api/cards/#{card_id}/card-memberships/userId:#{user_id}")

    def move_card(card_id, list_id, position: Position::MOVE_DEFAULT)
      response = request(:patch, "/api/cards/#{card_id}", { listId: list_id, position: })
      raise InvalidResponse, "Invalid moved card response" if @validate_responses && !response["item"].is_a?(Hash)

      response.fetch("item")
    end

    def comment(card_id, text) = request(:post, "/api/cards/#{card_id}/comments", { text: })

    class HTTPError < Error
      attr_reader :status

      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    ServerError = Class.new(Error)
    # A write failed after Planka may already have applied it.
    UnknownOutcome = Class.new(Error)

    # Failures before the request reaches Planka cannot have changed anything.
    UNSENT = [Errno::ECONNREFUSED, Net::OpenTimeout, SocketError].freeze
    # Failures after the request was sent leave a write's outcome unknown:
    # Planka may have applied the change.
    UNKNOWN = [ServerError, Errno::ECONNRESET, Net::ReadTimeout, EOFError].freeze
    # Every failure to reach Planka or keep a connection to it.
    NETWORK_ERRORS = [SystemCallError, SocketError, Timeout::Error, EOFError, IOError, OpenSSL::SSL::SSLError].freeze

    # Whether a failed request certainly left Planka unchanged: Planka rejected
    # it with an HTTP status, or it never reached Planka.
    def self.unapplied?(error) = error.is_a?(HTTPError) || UNSENT.any? { |type| error.is_a?(type) }

    # Sends each request exactly once; nothing is retried. A write that fails
    # after reaching Planka raises UnknownOutcome so the caller reads back.
    def request(method, path, body = nil)
      send_request(method, path, body)
    rescue *UNKNOWN => e
      raise if method == :get

      raise UnknownOutcome, "#{method.upcase} #{path}: #{e.class} (outcome unknown, reconcile by reading back)"
    end

    private

    # The record a write returns; canonical sessions reject a missing record.
    def item(response, kind)
      raise InvalidResponse, "Invalid #{kind} response" if @validate_responses && !response["item"].is_a?(Hash)

      response.fetch("item")
    end

    def send_request(method, path, body)
      http = Net::HTTP.new(@base.host, @base.port)
      http.max_retries = 0
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

      document = JSON.parse(res.body)
      raise InvalidResponse, "Invalid response document" if @validate_responses && !document.is_a?(Hash)

      document
    rescue JSON::ParserError
      raise InvalidResponse, "Invalid response JSON" if @validate_responses

      raise
    end
  end
end
