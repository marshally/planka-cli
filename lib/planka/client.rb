require "json"
require "net/http"
require "uri"
require_relative "position"
require_relative "records"

module Planka
  # A signed-in session against Planka's REST API as the board's bot user.
  class Client
    # Canonical sessions reject malformed documents near the request. Legacy
    # sessions skip the checks, so fetch and JSON failures keep their original
    # types. A check's block runs only when checks apply.
    module StrictResponses
      def self.check!(message) = (yield or raise InvalidResponse, message)
      def self.unparsable!(_error) = raise(InvalidResponse, "Invalid response JSON")
    end

    module LenientResponses
      def self.check!(_message) = nil
      def self.unparsable!(error) = raise(error)
    end

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
      @responses = validate_responses ? StrictResponses : LenientResponses
      @base = URI(base_url)
      @token = nil
    end

    def sign_in(email, password)
      response = request(:post, "/api/access-tokens", { emailOrUsername: email, password: password })
      @responses.check!("Invalid authentication response") do
        response.is_a?(Hash) && response["item"].is_a?(String) && !response["item"].empty?
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
      @responses.check!("Invalid board response") { response["included"].is_a?(Hash) }

      response.fetch("included")
    end

    # The board item with its included records; #board returns only the latter.
    def board_document(id)
      document = request(:get, "/api/boards/#{id}")
      @responses.check!("Invalid board response") { document["item"].is_a?(Hash) && document["included"].is_a?(Hash) }

      document
    end

    # One project and all boards visible to the authenticated caller, without paging.
    def project_document(id)
      document = request(:get, "/api/projects/#{id}")
      @responses.check!("Invalid project response") { document["item"].is_a?(Hash) && document["included"].is_a?(Hash) }

      document
    end

    # A finite (active or closed) list; Planka answers 404 for archive and trash.
    def list(id)
      response = request(:get, "/api/lists/#{id}")
      @responses.check!("Invalid list response") { response["item"].is_a?(Hash) }

      response.fetch("item")
    end

    # A task list with its tasks; Planka answers 404 when it is missing or not visible.
    def task_list(id)
      response = request(:get, "/api/task-lists/#{id}")
      @responses.check!("Invalid task list response") { response["item"].is_a?(Hash) }

      response.fetch("item")
    end

    def comments(card_id)
      response = request(:get, "/api/cards/#{card_id}/comments")
      @responses.check!("Invalid comments response") { response["items"].is_a?(Array) }

      response.fetch("items")
    end

    # Canonical paging is separate from the legacy one-page comments read.
    def comments_page(card_id, before_id: nil)
      query = before_id ? "?#{URI.encode_www_form(beforeId: before_id)}" : ""
      response = request(:get, "/api/cards/#{card_id}/comments#{query}")
      @responses.check!("Invalid comments response") { response["items"].is_a?(Array) }

      response.fetch("items")
    end

    def card(id) = request(:get, "/api/cards/#{id}")

    # Cards in a list, newest-position last, as GET returns them.
    def list_cards(list_id) = request(:get, "/api/lists/#{list_id}/cards")

    # Creates return the new record under "item".
    def create_board(project_id, **attrs) = item(request(:post, "/api/projects/#{project_id}/boards", attrs), "board")
    def update_board(board_id, **attrs) = item(request(:patch, "/api/boards/#{board_id}", attrs), "board")
    def delete_board(board_id) = item(request(:delete, "/api/boards/#{board_id}"), "board")

    def create_card(list_id, **attrs) = item(request(:post, "/api/lists/#{list_id}/cards", attrs), "card")

    def update_card(card_id, **attrs) = item(request(:patch, "/api/cards/#{card_id}", attrs), "card")

    def delete_card(card_id) = item(request(:delete, "/api/cards/#{card_id}"), "card")

    def create_list(board_id, **attrs) = item(request(:post, "/api/boards/#{board_id}/lists", attrs), "list")

    def update_list(list_id, **attrs) = item(request(:patch, "/api/lists/#{list_id}", attrs), "list")

    def delete_list(list_id) = item(request(:delete, "/api/lists/#{list_id}"), "list")

    def create_label(board_id, **attrs) = item(request(:post, "/api/boards/#{board_id}/labels", attrs), "label")

    def update_label(label_id, **attrs) = item(request(:patch, "/api/labels/#{label_id}", attrs), "label")

    def delete_label(label_id) = item(request(:delete, "/api/labels/#{label_id}"), "label")

    def add_card_label(card_id, label_id) = request(:post, "/api/cards/#{card_id}/card-labels", { labelId: label_id })

    def remove_card_label(card_id, label_id) = request(:delete, "/api/cards/#{card_id}/card-labels/labelId:#{label_id}")

    def create_task_list(card_id, **attrs) = item(request(:post, "/api/cards/#{card_id}/task-lists", attrs), "task list")

    def update_task_list(task_list_id, **attrs) = item(request(:patch, "/api/task-lists/#{task_list_id}", attrs), "task list")

    def delete_task_list(task_list_id) = item(request(:delete, "/api/task-lists/#{task_list_id}"), "task list")

    def update_task(id, **attrs) = request(:patch, "/api/tasks/#{id}", attrs)["item"]

    def create_task(task_list_id, **attrs) = item(request(:post, "/api/task-lists/#{task_list_id}/tasks", attrs), "task")

    def me
      response = request(:get, "/api/users/me")
      @responses.check!("Invalid signed-in user response") { response["item"].is_a?(Hash) }

      response.fetch("item")
    end

    def delete_project(id) = item(request(:delete, "/api/projects/#{id}"), "project")

    def update_project(id, **attributes) = item(request(:patch, "/api/projects/#{id}", attributes), "project")

    def create_project(**attributes) = item(request(:post, "/api/projects", attributes), "project")

    def project(id) = item(request(:get, "/api/projects/#{id}"), "project")

    def projects
      response = request(:get, "/api/projects")
      @responses.check!("Invalid projects response") { response["items"].is_a?(Array) }

      response.fetch("items")
    end

    # Every board the signed-in user can see, across projects.
    def board_ids
      document = request(:get, "/api/projects")
      @responses.check!("Invalid accessible board records") do
        boards = document["included"].is_a?(Hash) && document["included"]["boards"]
        boards.is_a?(Array) && boards.all? { |board| board.is_a?(Hash) && Records.id?(board["id"]) }
      end
      document.dig("included", "boards").map { |board| board["id"] }
    end

    def add_card_member(card_id, user_id) = request(:post, "/api/cards/#{card_id}/card-memberships", { userId: user_id })
    def remove_card_member(card_id, user_id) = request(:delete, "/api/cards/#{card_id}/card-memberships/userId:#{user_id}")

    def move_card(card_id, list_id, position: Position::MOVE_DEFAULT)
      response = request(:patch, "/api/cards/#{card_id}", { listId: list_id, position: })
      @responses.check!("Invalid moved card response") { response["item"].is_a?(Hash) }

      response.fetch("item")
    end

    def comment(card_id, text) = request(:post, "/api/cards/#{card_id}/comments", { text: })

    def create_comment(card_id, text:) = item(comment(card_id, text), "comment")
    def update_comment(id, text:) = item(request(:patch, "/api/comments/#{id}", { text: text }), "comment")
    def delete_comment(id) = item(request(:delete, "/api/comments/#{id}"), "comment")

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
      @responses.check!("Invalid #{kind} response") { response["item"].is_a?(Hash) }

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
      @responses.check!("Invalid response document") { document.is_a?(Hash) }
      document
    rescue JSON::ParserError => e
      @responses.unparsable!(e)
    end
  end
end
