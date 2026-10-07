require "minitest/autorun"
require "planka"
require_relative "fake_planka"
require_relative "relationship_contract"

class CardLabelsResourceTest < Minitest::Test
  include RelationshipContract

  def setup = @server = FakePlanka.new
  def teardown = @server.stop

  def duplicate_relationship_name = @server.add_label("enhancement")

  def with_relationship
    Planka::Client.session(base_url: @server.base_url, email: "bot@example.com", password: "fixture", validate_responses: true) do |client|
      labels = Planka::Cards::Labels.new(client, card_id: FakePlanka::PARENT_CARD)
      yield labels, FakePlanka::LABEL_ENHANCEMENT, "enhancement"
    end
  end
end
