require_relative "fake_planka"
require "uri"

# Native comment paging and mutations, isolated from the legacy handoff fixtures.
class FakeComments < FakePlanka
  def initialize
    super
    comments.each { |comment| comment["userId"] = "123" }
  end

  private

  def route(method, path, body)
    uri = URI(path)
    case [method, uri.path.split("/").reject(&:empty?)]
    in ["GET", ["api", "cards", id, "comments"]]
      before = URI.decode_www_form(uri.query.to_s).to_h["beforeId"]
      records = comments.select { |comment| comment["cardId"] == id && (!before || comment["id"].to_i < before.to_i) }
      [200, { "items" => records.sort_by { |comment| -comment["id"].to_i }.first(50) }]
    in ["POST", ["api", "cards", id, "comments"]]
      record = make_comment(id, JSON.parse(body)).merge!("userId" => "123")
      [200, { "item" => record }]
    in ["PATCH", ["api", "comments", id]]
      record = comments.find { |comment| comment["id"] == id }
      record ? [200, { "item" => record.merge!(JSON.parse(body)) }] : [404, {}]
    in ["DELETE", ["api", "comments", id]]
      record = comments.find { |comment| comment["id"] == id }
      comments.delete(record)
      record ? [200, { "item" => record }] : [404, {}]
    else
      super
    end
  end
end
