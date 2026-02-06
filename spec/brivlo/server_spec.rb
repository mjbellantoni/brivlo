# frozen_string_literal: true

require "spec_helper"
require "json"
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

  describe "POST /events" do
    let(:valid_token) { "test-secret-token" }
    let(:valid_event) do
      {
        event_id: "uuid-123",
        ts: "2026-02-06T12:00:00Z",
        event: "wait.permission",
        instance: "wt-a",
        host: "mjb-dev-01",
        card: "123",
        tool: "Bash",
        summary: "Needs approval"
      }.to_json
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("BRIVLO_TOKEN", nil).and_return(valid_token)
    end

    it "returns 401 without auth token" do
      post "/events", valid_event, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(401)
    end

    it "returns 401 with wrong token" do
      post "/events", valid_event,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer wrong-token"

      expect(last_response.status).to eq(401)
    end

    it "returns 201 with valid token and stores event" do
      post "/events", valid_event,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"

      expect(last_response.status).to eq(201)
      expect(db[:events].count).to eq(1)
      expect(db[:events].first[:event_id]).to eq("uuid-123")
    end

    it "deduplicates by event_id" do
      2.times do
        post "/events", valid_event,
             "CONTENT_TYPE" => "application/json",
             "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"
      end

      expect(db[:events].count).to eq(1)
    end

    it "stores all event fields" do
      event_with_meta = JSON.parse(valid_event).merge("meta" => { "foo" => "bar" }.to_json).to_json

      post "/events", event_with_meta,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"

      stored = db[:events].first
      expect(stored[:event]).to eq("wait.permission")
      expect(stored[:instance]).to eq("wt-a")
      expect(stored[:host]).to eq("mjb-dev-01")
      expect(stored[:card]).to eq("123")
      expect(stored[:tool]).to eq("Bash")
      expect(stored[:summary]).to eq("Needs approval")
      expect(stored[:received_at]).not_to be_nil
    end
  end
end
