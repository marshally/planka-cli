require_relative "fake_planka"

# Community v2.2.1 project routes, sharing the HTTP/session/fault boundary.
class FakeProjectPlanka < FakePlanka
  PROJECT_ID = "100000000000000010".freeze
  attr_reader :projects

  private

  def seed
    super
    @projects = [{ "id" => PROJECT_ID, "name" => "Product", "description" => "A roadmap",
                   "ownerProjectManagerId" => "900", "createdAt" => nil, "updatedAt" => nil }]
  end

  def route(method, path, body)
    data = body.to_s.empty? ? {} : JSON.parse(body)
    case [method, path.split("/").reject(&:empty?)]
    in ["GET", ["api", "projects"]] then [200, { "items" => @projects, "included" => { "boards" => boards } }]
    in ["GET", ["api", "projects", id]]
      record = @projects.find { |project| project["id"] == id }
      record ? [200, { "item" => record, "included" => {} }] : [404, {}]
    in ["DELETE", ["api", "projects", id]]
      record = @projects.find { |project| project["id"] == id }
      return [404, {}] unless record
      return [422, { "message" => "Must not have boards" }] if boards.any? { |board| board["projectId"] == id }

      @projects.delete(record)
      [200, { "item" => record }]
    in ["PATCH", ["api", "projects", id]]
      record = @projects.find { |project| project["id"] == id }
      record ? [200, { "item" => record.merge!(data) }] : [404, {}]
    in ["POST", ["api", "projects"]]
      manager_id = next_id
      record = { "id" => next_id, "name" => data["name"], "description" => data["description"],
                 "ownerProjectManagerId" => data["type"] == "private" ? manager_id : nil,
                 "createdAt" => nil, "updatedAt" => nil }
      @projects << record
      [200, { "item" => record, "included" => { "projectManagers" => [{ "id" => manager_id, "projectId" => record["id"], "userId" => "800" }] } }]
    else super
    end
  end
end
