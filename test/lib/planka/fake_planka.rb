require "socket"
require "json"
require "openssl"
require "uri"

# A small in-memory Planka that speaks the REST endpoints the CLI uses, so the
# publishing commands can be driven end to end over real HTTP without a live
# board. State accumulates across requests, so a test can create a card and then
# read it back. Faults can be injected to exercise retries, partial creates and
# unknown outcomes.
class FakePlanka
  # Ids are numeric strings because card commands accept an id or a card URL and
  # extract the trailing digits, and a list id is told from a list name by being
  # all digits.
  BOARD_ID = "100000000000000001".freeze
  LIST_READY = "200000000000000001".freeze
  LIST_PROGRESS = "200000000000000002".freeze
  LIST_DONE = "200000000000000003".freeze
  LABEL_ENHANCEMENT = "300000000000000001".freeze
  PARENT_CARD = "400000000000000001".freeze
  FINITE_TYPES = %w[active closed].freeze
  attr_reader :requests
  # Endless (archive/trash) list pages hold this many cards, as Planka's 50.
  attr_accessor :page_size

  def initialize(tls_failure_after: nil)
    @tls_failure_after = tls_failure_after
    if tls_failure_after
      @trusted_context = tls_context
      @untrusted_context = tls_context
    end
    @seq = 1_900_000_000_000_000_000
    @requests = []
    @faults = []
    @page_size = 50
    @lock = Mutex.new
    seed
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { serve }
  end

  def base_url = "#{@tls_failure_after ? "https" : "http"}://127.0.0.1:#{@server.addr[1]}"
  def trusted_certificate = @trusted_context.cert.to_pem
  def board_id = BOARD_ID

  def stop
    @server.close
    @thread.join(2) || @thread.kill
  end

  def counts(method, path_regex) = @requests.count { |m, p, _| m == method && p.match?(path_regex) }

  # Injects `times` one-shot faults after `skip` clean matches: :drop closes
  # before handling (nothing applied), :apply_then_drop mutates then closes
  # (outcome unknown to the client), :server_error returns a 500 without handling.
  def inject(method, pattern, kind, times: 1, skip: 0)
    @faults << { method: method.to_s.upcase, pattern:, kind:, remaining: times, skip: }
  end

  # Adds another list or label with an existing name, to test ambiguous name
  # resolution.
  def add_list(name, type = "active", board_id: BOARD_ID)
    record = list(next_id, name, type).merge("boardId" => board_id)
    @state[:lists] << record
    record["id"]
  end

  def add_board(id) = @boards << { "id" => id }

  def add_card(name, list_id, position: 65_536, list_changed_at: "2026-09-01T00:00:00.000Z")
    board_id = @state[:lists].find { |entry| entry["id"] == list_id }.fetch("boardId")
    record = card(next_id, name, list_id, nil).merge("boardId" => board_id, "position" => position, "listChangedAt" => list_changed_at)
    @state[:cards] << record
    record["id"]
  end

  def add_label(name) = @state[:labels] << label(next_id, name, "lagoon-blue")

  # Current state, for assertions.
  def cards = @state[:cards]
  def labels = @state[:labels]
  def task_lists = @state[:taskLists]
  def tasks = @state[:tasks]
  def card_labels = @state[:cardLabels]
  def memberships = @state[:cardMemberships]
  def users = @state[:users]
  def board_memberships = @state[:boardMemberships]
  def comments = @state[:comments]
  def lists = @state[:lists]
  def boards = @boards
  def find_card(id) = @state[:cards].find { |c| c["id"] == id }

  private

  # Each context uses a different self-signed certificate. Tests trust only the
  # first, allowing a real TLS handshake failure at sign-in or cleanup.
  def tls_context
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=127.0.0.1")
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(factory.create_extension("subjectAltName", "IP:127.0.0.1"))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    context = OpenSSL::SSL::SSLContext.new
    context.cert = cert
    context.key = key
    context
  end

  def seed
    @boards = [{ "id" => BOARD_ID }]
    @state = {
      lists: [
        list(LIST_READY, "ready-for-agent", "active"),
        list(LIST_PROGRESS, "in-progress", "active"),
        list(LIST_DONE, "done", "closed"),
      ],
      labels: [label(LABEL_ENHANCEMENT, "enhancement", "berry-red")],
      cards: [card(PARENT_CARD, "Spec: Work-next refinement", LIST_READY, "Original description.")],
      cardLabels: [],
      taskLists: [],
      tasks: [],
      cardMemberships: [],
      users: [],
      boardMemberships: [],
      comments: [{ "id" => "500000000000000001", "cardId" => PARENT_CARD, "text" => "Parent context note.", "userId" => "user-human", "createdAt" => "2026-09-01T00:00:00.000Z" }],
    }
  end

  def list(id, name, type) = { "id" => id, "name" => name, "type" => type, "boardId" => BOARD_ID, "position" => 65_536 }
  def label(id, name, color) = { "id" => id, "name" => name, "color" => color, "boardId" => BOARD_ID, "position" => 65_536 }
  def card(id, name, list_id, description) = { "id" => id, "name" => name, "listId" => list_id, "boardId" => BOARD_ID, "description" => description, "type" => "project", "position" => 65_536, "createdAt" => "2026-09-01T00:00:00.000Z" }

  def next_id = (@seq += 1).to_s

  def serve
    loop do
      socket = @server.accept
      if @tls_failure_after
        context = @requests.size < @tls_failure_after ? @trusted_context : @untrusted_context
        socket = OpenSSL::SSL::SSLSocket.new(socket, context)
        socket.sync_close = true
        begin
          socket.accept
        rescue OpenSSL::SSL::SSLError
          socket.close
          next
        end
      end
      handle(socket)
    end
  rescue IOError, Errno::EBADF, Errno::EINVAL
    nil # server closed
  end

  def handle(socket)
    line = socket.gets or return
    method, path, = line.split
    headers = {}
    while (header = socket.gets) && header != "\r\n"
      key, value = header.split(":", 2)
      headers[key.downcase] = value.strip
    end
    body = socket.read(headers.fetch("content-length", "0").to_i)
    @lock.synchronize { dispatch(socket, method, path, body) }
  ensure
    socket.close
  end

  def dispatch(socket, method, path, body)
    @requests << [method, path, body]
    case (fault = take_fault(method, path))
    when Hash then return write(socket, 200, fault)
    when Integer then return write(socket, fault, { "message" => "private upstream body" })
    when :malformed_projects then return write(socket, 200, { "included" => { "boards" => nil } })
    when :unsafe_board_id then return write(socket, 200, { "included" => { "boards" => [{ "id" => "../users/me" }] } })
    when :malformed_user then return write(socket, 200, { "item" => nil })
    when :malformed_comments then return write(socket, 200, { "items" => [{ "text" => 42, "createdAt" => "2026-10-01T00:00:00Z" }] })
    when :malformed_board then return write(socket, 200, { "included" => { "lists" => "invalid" } })
    when :malformed_branch_title
      payload = board_payload(BOARD_ID)
      payload["included"]["cards"] = payload["included"]["cards"].map { |card| card.merge("name" => 42) }
      return write(socket, 200, payload)
    when :malformed_feature_label
      payload = board_payload(BOARD_ID)
      payload["included"]["labels"] = [{ "id" => "991", "name" => 42 }]
      payload["included"]["cardLabels"] = [{ "cardId" => PARENT_CARD, "labelId" => "991" }]
      return write(socket, 200, payload)
    when :missing_feature_label
      payload = board_payload(BOARD_ID)
      payload["included"]["cardLabels"] = [{ "cardId" => PARENT_CARD, "labelId" => "991" }]
      return write(socket, 200, payload)
    when :missing_board_records then return write(socket, 200, { "included" => { "cards" => [] } })
    when :malformed_criteria
      payload = board_payload(BOARD_ID)
      payload["included"]["tasks"] = [{ "taskListId" => "999", "name" => 42, "isCompleted" => false }]
      return write(socket, 200, payload)
    when :invalid_token then return write(socket, 200, { "item" => { "private" => "private upstream body" } })
    when :malformed_auth then return write(socket, 200, [])
    when :malformed_card then return write(socket, 200, { "item" => nil, "included" => {} })
    when :malformed_board_reference then return write(socket, 200, { "item" => { "boardId" => "not-an-id" } })
    when :malformed_board_path then return write(socket, 200, { "item" => { "boardId" => "../cards/123" } })
    when :malformed_description then return write(socket, 200, { "item" => { "id" => PARENT_CARD, "description" => 42 }, "included" => {} })
    when :malformed_card_page then return write(socket, 200, { "items" => [{ "id" => 42 }], "included" => {} })
    when :malformed_included then return write(socket, 200, { "item" => find_card(PARENT_CARD), "included" => [] })
    when :drop then return
    when :server_error then return write(socket, 500, { "message" => "injected failure" })
    when :apply_then_drop
      route(method, path, body)
      return
    end
    status, payload = route(method, path, body)
    write(socket, status, payload)
  end

  def take_fault(method, path)
    fault = @faults.find { |f| f[:method] == method && path.match?(f[:pattern]) && (f[:skip].positive? || f[:remaining].positive?) }
    return nil unless fault

    if fault[:skip].positive?
      fault[:skip] -= 1
      return nil
    end

    fault[:remaining] -= 1
    fault[:kind]
  end

  def write(socket, status, payload)
    json = JSON.generate(payload)
    socket.write "HTTP/1.1 #{status} #{status == 200 ? "OK" : "Error"}\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}"
  end

  def route(method, path, body)
    data = body.to_s.empty? ? {} : JSON.parse(body)
    path, query = path.split("?", 2)
    query = URI.decode_www_form(query.to_s).to_h
    seg = path.split("/").reject(&:empty?)
    case [method, seg]
    in ["PATCH", ["api", "tasks", id]]
      task = @state[:tasks].find { |entry| entry["id"] == id }
      task.merge!(data)
      [200, { "item" => task }]
    in ["POST", ["api", "access-tokens"]] then [200, { "item" => "fake-token" }]
    in ["DELETE", ["api", "access-tokens", "me"]] then [200, {}]
    in ["GET", ["api", "boards", id]] then [200, board_payload(id)]
    in ["GET", ["api", "users", "me"]] then [200, { "item" => { "id" => "user-bot" } }]
    in ["GET", ["api", "projects"]] then [200, { "included" => { "boards" => @boards } }]
    in ["GET", ["api", "cards", id, "comments"]] then [200, { "items" => comments_for(id) }]
    in ["GET", ["api", "cards", id]] then [200, card_payload(id)]
    in ["GET", ["api", "lists", id, "cards"]] then [200, list_cards_page(id, query)]
    in ["GET", ["api", "lists", id]] then list_payload(id)
    in ["DELETE", ["api", "cards", id]] then [200, { "item" => delete_card(id) }]
    in ["POST", ["api", "boards", id, "lists"]] then [200, { "item" => make_list(id, data) }]
    in ["POST", ["api", "lists", id, "cards"]] then [200, { "item" => make_card(id, data) }]
    in ["PATCH", ["api", "cards", id]] then [200, { "item" => patch_card(id, data) }]
    in ["POST", ["api", "boards", id, "labels"]] then [200, { "item" => make_label(id, data) }]
    in ["DELETE", ["api", "cards", id, "card-labels", label_ref]]
      label_id = label_ref.delete_prefix("labelId:")
      @state[:cardLabels].reject! { |entry| entry["cardId"] == id && entry["labelId"] == label_id }
      [200, { "item" => { "cardId" => id, "labelId" => label_id } }]
    in ["POST", ["api", "cards", id, "card-labels"]] then [200, { "item" => make_card_label(id, data) }]
    in ["POST", ["api", "cards", id, "card-memberships"]] then [200, { "item" => make_membership(id, data) }]
    in ["DELETE", ["api", "cards", id, "card-memberships", user]]
      record = memberships.find { |member| member["cardId"] == id && "userId:#{member["userId"]}" == user }
      memberships.delete(record)
      [200, { "item" => record }]
    in ["POST", ["api", "cards", id, "comments"]] then [200, { "item" => make_comment(id, data) }]
    in ["POST", ["api", "cards", id, "task-lists"]] then [200, { "item" => make_task_list(id, data) }]
    in ["PATCH", ["api", "task-lists", id]] then [200, { "item" => patch_task_list(id, data) }]
    in ["POST", ["api", "task-lists", id, "tasks"]] then [200, { "item" => make_task(id, data) }]
    else [404, { "message" => "no route for #{method} #{path}" }]
    end
  rescue StandardError => e
    [500, { "message" => e.message }]
  end

  # Board reads include only cards in finite (active/closed) lists; archive and
  # trash cards are paged through GET /api/lists/:id/cards.
  def board_payload(id)
    endless = @state[:lists].reject { |list| FINITE_TYPES.include?(list["type"]) }.map { |list| list["id"] }
    cards = @state[:cards].select { |card| card["boardId"] == id && !endless.include?(card["listId"]) }
    card_ids = cards.map { |card| card["id"] }
    task_lists = @state[:taskLists].select { |list| card_ids.include?(list["cardId"]) }
    task_list_ids = task_lists.map { |list| list["id"] }
    included = {
      "lists" => @state[:lists].select { |list| list["boardId"] == id },
      "cards" => cards, "labels" => @state[:labels].select { |label| label["boardId"] == id },
      "cardLabels" => @state[:cardLabels].select { |relation| card_ids.include?(relation["cardId"]) },
      "taskLists" => task_lists, "tasks" => @state[:tasks].select { |task| task_list_ids.include?(task["taskListId"]) },
      "cardMemberships" => @state[:cardMemberships].select { |record| card_ids.include?(record["cardId"]) },
      "users" => users,
      "boardMemberships" => board_memberships.select { |record| record["boardId"] == id }
    }
    { "item" => { "id" => id, "name" => "Board", "defaultCardType" => "project" }, "included" => included }
  end

  def list_payload(id)
    record = @state[:lists].find { |list| list["id"] == id }
    return [404, { "message" => "List not found" }] unless record && FINITE_TYPES.include?(record["type"])

    [200, { "item" => record, "included" => {} }]
  end

  # Pages by listChangedAt then id, newest first, as Planka's endless lists do.
  def list_cards_page(id, query)
    cards = @state[:cards].select { |card| card["listId"] == id }
                          .sort_by { |card| [card["listChangedAt"].to_s, card["id"].to_i] }.reverse
    if query["before[id]"]
      cursor = [query.fetch("before[listChangedAt]"), query.fetch("before[id]").to_i]
      cards = cards.select { |card| ([card["listChangedAt"].to_s, card["id"].to_i] <=> cursor).negative? }
    end
    cards = cards.first(@page_size)
    ids = cards.map { |card| card["id"] }
    { "items" => cards, "included" => { "cardLabels" => @state[:cardLabels].select { |record| ids.include?(record["cardId"]) },
                                        "cardMemberships" => @state[:cardMemberships].select { |record| ids.include?(record["cardId"]) } } }
  end

  def delete_card(id)
    record = fetch(@state[:cards], id)
    @state[:cards].delete(record)
    record
  end

  def card_payload(id)
    card = fetch(@state[:cards], id)
    list_ids = @state[:taskLists].select { |tl| tl["cardId"] == id }.map { |tl| tl["id"] }
    {
      "item" => card,
      "included" => {
        "cardMemberships" => @state[:cardMemberships].select { |m| m["cardId"] == id },
        "cardLabels" => @state[:cardLabels].select { |cl| cl["cardId"] == id },
        "taskLists" => @state[:taskLists].select { |tl| tl["cardId"] == id },
        "tasks" => @state[:tasks].select { |t| list_ids.include?(t["taskListId"]) },
      },
    }
  end

  def comments_for(id) = @state[:comments].select { |c| c["cardId"] == id }

  def make_list(board_id, data)
    list = { "id" => next_id, "boardId" => board_id, "name" => data["name"], "type" => data["type"], "position" => data["position"] }
    @state[:lists] << list
    list
  end

  def make_card(list_id, data)
    # Planka rejects an empty-string description; the field must be absent or set.
    raise "empty description" if data["description"] == ""

    list = @state[:lists].find { |entry| entry["id"] == list_id }
    card = { "id" => next_id, "name" => data["name"], "description" => data["description"], "type" => data["type"], "listId" => list_id,
             "boardId" => list ? list["boardId"] : BOARD_ID, "position" => FINITE_TYPES.include?(list&.dig("type") || "active") ? data["position"] : nil,
             "createdAt" => "2026-10-01T00:00:00.000Z", "listChangedAt" => "2026-10-01T00:00:00.000Z" }
    @state[:cards] << card
    card
  end

  def patch_card(id, data)
    card = fetch(@state[:cards], id)
    %w[name description listId position].each { |key| card[key] = data[key] if data.key?(key) }
    card
  end

  def make_label(board_id, data)
    label = { "id" => next_id, "name" => data["name"], "color" => data["color"], "boardId" => board_id, "position" => data["position"] }
    @state[:labels] << label
    label
  end

  def make_card_label(card_id, data)
    record = { "id" => next_id, "cardId" => card_id, "labelId" => data["labelId"] }
    @state[:cardLabels] << record
    record
  end

  def make_membership(card_id, data)
    record = { "id" => next_id, "cardId" => card_id, "userId" => data["userId"], "createdAt" => Time.now.utc.iso8601 }
    @state[:cardMemberships] << record
    record
  end

  def make_comment(card_id, data)
    record = { "id" => next_id, "cardId" => card_id, "text" => data["text"], "userId" => "user-bot", "createdAt" => "2026-10-01T00:00:00.000Z" }
    @state[:comments] << record
    record
  end

  def make_task_list(card_id, data)
    record = { "id" => next_id, "cardId" => card_id, "name" => data["name"] || "Tasks", "position" => data["position"], "showOnFrontOfCard" => data["showOnFrontOfCard"] }
    @state[:taskLists] << record
    record
  end

  def patch_task_list(id, data)
    task_list = fetch(@state[:taskLists], id)
    task_list["name"] = data["name"] if data.key?("name")
    task_list
  end

  def make_task(task_list_id, data)
    linked = data["linkedCardId"]
    completed = linked ? closed?(linked) : (data["isCompleted"] || false)
    record = { "id" => next_id, "taskListId" => task_list_id, "name" => data["name"], "linkedCardId" => linked, "isCompleted" => completed, "position" => data["position"] }
    @state[:tasks] << record
    record
  end

  def closed?(card_id)
    card = @state[:cards].find { |c| c["id"] == card_id } or return false
    list = @state[:lists].find { |l| l["id"] == card["listId"] }
    list && list["type"] == "closed"
  end

  def fetch(collection, id)
    collection.find { |record| record["id"] == id } || raise("no record #{id}")
  end
end
