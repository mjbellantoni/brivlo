# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "brivlo/server"

RSpec.describe Brivlo::Server do
  include Rack::Test::Methods

  let(:db) { Sequel.sqlite }

  def app
    described_class.new(db: db)
  end

  describe "GET /ping" do
    it "returns 200 ok" do
      get "/ping"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("ok")
    end
  end
end
