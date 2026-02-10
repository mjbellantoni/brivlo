# frozen_string_literal: true

require "spec_helper"
require "json"
require "securerandom"
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

    it "deduplicates by event_id and returns 200" do
      post "/events", valid_event,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"
      expect(last_response.status).to eq(201)

      post "/events", valid_event,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"
      expect(last_response.status).to eq(200)

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

  describe "GET /board" do
    before do
      Brivlo::Database.setup(db)
    end

    let(:now) { Time.now.utc }

    def insert_event(overrides = {})
      defaults = {
        event_id: SecureRandom.uuid,
        ts: now.iso8601,
        event: "task.start",
        instance: "wt-a",
        host: "mjb-dev-01",
        received_at: now.iso8601
      }
      db[:events].insert(defaults.merge(overrides))
    end

    it "renders an HTML page" do
      get "/board"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
    end

    it "shows instance status rows" do
      insert_event(instance: "wt-a", event: "task.start")

      get "/board"

      expect(last_response.body).to include("wt-a")
      expect(last_response.body).to include("mjb-dev-01")
    end

    it "shows waiting status for wait.* events" do
      insert_event(instance: "wt-a", event: "wait.permission", tool: "Bash", summary: "Needs approval")

      get "/board"

      expect(last_response.body).to include("waiting")
      expect(last_response.body).to include("Bash")
      expect(last_response.body).to include("Needs approval")
    end

    it "shows active status for non-wait events" do
      insert_event(instance: "wt-b", event: "task.start")

      get "/board"

      expect(last_response.body).to include("active")
    end

    it "uses the latest event per instance for status" do
      insert_event(instance: "wt-a", event: "wait.permission", ts: (now - 60).iso8601)
      insert_event(instance: "wt-a", event: "task.start", ts: now.iso8601)

      get "/board"

      # Latest is task.start, so should be active, not waiting
      expect(last_response.body).to include("active")
    end

    it "sorts waiting instances first" do
      insert_event(instance: "wt-active", event: "task.start", ts: now.iso8601)
      insert_event(instance: "wt-waiting", event: "wait.permission", ts: (now - 30).iso8601)

      get "/board"

      body = last_response.body
      waiting_pos = body.index("wt-waiting")
      active_pos = body.index("wt-active")
      expect(waiting_pos).to be < active_pos
    end

    it "includes auto-refresh meta tag" do
      get "/board"

      expect(last_response.body).to include('http-equiv="refresh"')
    end

    it "links instance names to detail pages" do
      insert_event(instance: "wt-a", event: "task.start")

      get "/board"

      expect(last_response.body).to include('href="/board/wt-a"')
    end

    describe "top wait reasons" do
      it "shows wait reasons grouped by event and tool" do
        3.times { insert_event(event: "wait.permission", tool: "Bash") }
        insert_event(event: "wait.permission", tool: "Edit")

        get "/board"

        expect(last_response.body).to include("Top Wait Reasons")
        expect(last_response.body).to include("wait.permission")
      end

      it "shows counts for each wait reason" do
        3.times { insert_event(event: "wait.permission", tool: "Bash") }

        get "/board"

        expect(last_response.body).to include("3")
      end
    end
  end

  describe "GET /board/:instance" do
    before { Brivlo::Database.setup(db) }

    let(:now) { Time.now.utc }

    def insert_event(overrides = {})
      defaults = {
        event_id: SecureRandom.uuid,
        ts: now.iso8601,
        event: "task.start",
        instance: "wt-a",
        host: "mjb-dev-01",
        received_at: now.iso8601
      }
      db[:events].insert(defaults.merge(overrides))
    end

    it "shows event history for the instance" do
      insert_event(instance: "wt-a", event: "task.start", ts: (now - 60).iso8601)
      insert_event(instance: "wt-a", event: "wait.permission", ts: now.iso8601)
      insert_event(instance: "wt-b", event: "task.start")

      get "/board/wt-a"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("wt-a")
      expect(last_response.body).to include("task.start")
      expect(last_response.body).to include("wait.permission")
      expect(last_response.body).not_to include("wt-b")
    end

    it "limits to last 50 events" do
      55.times do |i|
        insert_event(instance: "wt-a", event: "task.#{i}", ts: (now - (55 - i)).iso8601)
      end

      get "/board/wt-a"

      expect(last_response.body).not_to include("task.0")
      expect(last_response.body).to include("task.54")
    end

    it "orders events most recent first" do
      insert_event(instance: "wt-a", event: "first", ts: (now - 60).iso8601)
      insert_event(instance: "wt-a", event: "second", ts: now.iso8601)

      get "/board/wt-a"

      body = last_response.body
      expect(body.index("second")).to be < body.index("first")
    end
  end
end
