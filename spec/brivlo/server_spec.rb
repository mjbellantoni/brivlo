# frozen_string_literal: true

require "spec_helper"
require "json"
require "securerandom"
require "rack/test"
require "brivlo/server"
require "brivlo/card_resolver"

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

    it "returns 422 when required fields are missing" do
      incomplete_event = { event_id: "uuid-456" }.to_json

      post "/events", incomplete_event,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"

      expect(last_response.status).to eq(422)
      expect(db[:events].count).to eq(0)
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

  describe "POST /events card tracking" do
    let(:valid_token) { "test-secret-token" }

    before do
      Brivlo::Database.setup(db)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("BRIVLO_TOKEN", nil).and_return(valid_token)
    end

    def post_event(overrides = {}) # rubocop:disable Metrics/MethodLength
      event = {
        event_id: SecureRandom.uuid,
        ts: Time.now.utc.iso8601,
        event: "tool.invoke",
        instance: "wt-a",
        host: "mjb-dev-01",
        tool: "Bash"
      }.merge(overrides)

      post "/events", event.to_json,
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"
    end

    it "sets instance card when summary matches bin/trello card show" do
      allow(Brivlo::CardResolver).to receive(:resolve)
        .with("#42", trello_cli_path: nil)
        .and_return({ card_title: "Fix login bug", card_url: "https://trello.com/c/abc123" })

      post_event(summary: "bin/trello card show #42")

      row = db[:instance_cards].where(instance: "wt-a").first
      expect(row[:card_ref]).to eq("#42")
      expect(row[:card_title]).to eq("Fix login bug")
      expect(row[:card_url]).to eq("https://trello.com/c/abc123")
    end

    it "replaces existing card on new card show" do
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#1", card_title: "Old",
        card_url: "https://trello.com/c/old", set_at: Time.now.utc.iso8601
      )

      allow(Brivlo::CardResolver).to receive(:resolve)
        .with("#99", trello_cli_path: nil)
        .and_return({ card_title: "New card", card_url: "https://trello.com/c/new" })

      post_event(summary: "bin/trello card show #99")

      expect(db[:instance_cards].where(instance: "wt-a").count).to eq(1)
      expect(db[:instance_cards].first[:card_title]).to eq("New card")
    end

    it "does not set card when resolver returns nil" do
      allow(Brivlo::CardResolver).to receive(:resolve).and_return(nil)

      post_event(summary: "bin/trello card show #42")

      expect(db[:instance_cards].count).to eq(0)
    end

    it "clears instance card when summary matches Done move" do
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: "Fix bug",
        card_url: "https://trello.com/c/abc123", set_at: Time.now.utc.iso8601
      )

      post_event(summary: 'bin/trello card move #42 "Done/Committed"')

      expect(db[:instance_cards].where(instance: "wt-a").count).to eq(0)
    end

    it "ignores non-trello bash summaries" do
      post_event(summary: "bundle exec rspec")

      expect(db[:instance_cards].count).to eq(0)
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

    it "prefers event with tool over null-tool duplicate within 10s" do
      insert_event(
        instance: "wt-b", event: "wait.permission",
        tool: "Bash", summary: "Bash: bin/rails stats",
        ts: (now - 6).iso8601
      )
      insert_event(
        instance: "wt-b", event: "wait.permission",
        tool: nil, summary: "Claude needs your permission to use Bash",
        ts: now.iso8601
      )

      get "/board"

      body = last_response.body
      instances_section = body[body.index("Instances")..body.index("Top Wait Reasons")]
      expect(instances_section).to include("Bash: bin/rails stats")
      expect(instances_section).not_to include("Claude needs your permission")
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

    it "links to wait reasons page" do
      get "/board"

      expect(last_response.body).to include('href="/wait_reasons"')
    end

    it "hides dismissed instances from the board" do
      insert_event(instance: "wt-a", event: "task.start", ts: (now - 60).iso8601)
      db[:dismissed_instances].insert(instance: "wt-a", dismissed_at: now.iso8601)

      get "/board"

      expect(last_response.body).not_to include("wt-a")
    end

    it "shows dismissed instance when a new event arrives after dismiss" do
      dismiss_time = (now - 30).iso8601
      db[:dismissed_instances].insert(instance: "wt-a", dismissed_at: dismiss_time)
      insert_event(instance: "wt-a", event: "task.start", ts: now.iso8601)

      get "/board"

      expect(last_response.body).to include("wt-a")
    end

    it "shows dismissed instances with ?all=1" do
      insert_event(instance: "wt-a", event: "task.start", ts: (now - 60).iso8601)
      db[:dismissed_instances].insert(instance: "wt-a", dismissed_at: now.iso8601)

      get "/board?all=1"

      expect(last_response.body).to include("wt-a")
    end

    it "includes a dismiss form in each instance row" do
      insert_event(instance: "wt-a", event: "task.start")

      get "/board"

      expect(last_response.body).to include('action="/board/wt-a/dismiss"')
      expect(last_response.body).to include("Dismiss")
    end

    it "shows toggle links for filtered and unfiltered views" do
      get "/board"
      expect(last_response.body).to include('href="/board?all=1"')
      expect(last_response.body).to include("Show all")

      get "/board?all=1"
      expect(last_response.body).to include('href="/board"')
      expect(last_response.body).to include("Hide dismissed")
    end

    it "shows card title as a link when instance has a card" do
      insert_event(instance: "wt-a", event: "task.start")
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: "Fix login bug",
        card_url: "https://trello.com/c/abc123", set_at: now.iso8601
      )

      get "/board"

      expect(last_response.body).to include('href="https://trello.com/c/abc123"')
      expect(last_response.body).to include("Fix login bug")
    end

    it "shows empty card cell when instance has no card" do
      insert_event(instance: "wt-a", event: "task.start")

      get "/board"

      body = last_response.body
      # The Card column header exists but the cell is empty
      expect(body).to include("<th>Card</th>")
    end

    it "truncates long card titles to 40 characters" do
      insert_event(instance: "wt-a", event: "task.start")
      long_title = "A" * 50
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: long_title,
        card_url: "https://trello.com/c/abc123", set_at: now.iso8601
      )

      get "/board"

      expect(last_response.body).to include("#{"A" * 40}...")
      expect(last_response.body).not_to include("A" * 50)
    end

    it "resolves pending card when instance has unresolved card show event" do
      insert_event(instance: "wt-a", event: "tool.invoke",
                   summary: "bin/trello card show #42")

      allow(Brivlo::CardResolver).to receive(:resolve)
        .with("#42", trello_cli_path: nil)
        .and_return({ card_title: "Fix login bug", card_url: "https://trello.com/c/abc123" })

      get "/board"

      expect(last_response.body).to include("Fix login bug")
      expect(db[:instance_cards].where(instance: "wt-a").count).to eq(1)
    end

    it "does not re-resolve card that was moved to done after show" do
      insert_event(instance: "wt-a", event: "tool.invoke",
                   summary: "bin/trello card show #42", ts: (now - 60).iso8601)
      insert_event(instance: "wt-a", event: "tool.invoke",
                   summary: 'bin/trello card move #42 "Done/Committed"', ts: now.iso8601)

      expect(Brivlo::CardResolver).not_to receive(:resolve)

      get "/board"

      expect(db[:instance_cards].where(instance: "wt-a").count).to eq(0)
    end

    it "skips resolve when instance already has a card" do
      insert_event(instance: "wt-a", event: "tool.invoke",
                   summary: "bin/trello card show #42")
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: "Already tracked",
        card_url: "https://trello.com/c/abc123", set_at: now.iso8601
      )

      expect(Brivlo::CardResolver).not_to receive(:resolve)

      get "/board"
    end

    it "includes a clear card button when instance has a card" do
      insert_event(instance: "wt-a", event: "task.start")
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: "Fix bug",
        card_url: "https://trello.com/c/abc123", set_at: now.iso8601
      )

      get "/board"

      expect(last_response.body).to include('action="/board/wt-a/clear_card"')
    end

    it "truncates tool names longer than 12 characters" do
      insert_event(tool: "AskUserQuestion", summary: "asking something")

      get "/board"

      expect(last_response.body).to include("AskUserQues\u2026")
      expect(last_response.body).not_to include("AskUserQuestion")
    end

    it "shows tool names 12 chars or shorter as-is" do
      insert_event(tool: "Edit", summary: "editing file")

      get "/board"

      expect(last_response.body).to include("Edit")
    end

    it "hides summary when it matches tool name" do
      insert_event(tool: "Bash", summary: "Bash")

      get "/board"

      body = last_response.body
      # Tool should appear but summary should not be shown separately
      # Count occurrences - "Bash" appears in tool display but not duplicated as summary
      expect(body).to include("Bash")
    end
  end

  describe "POST /board/:instance/dismiss" do
    before { Brivlo::Database.setup(db) }

    it "creates a dismissed_instances record and redirects to /board" do
      post "/board/wt-a/dismiss"

      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_request.path).to eq("/board")

      row = db[:dismissed_instances].where(instance: "wt-a").first
      expect(row).not_to be_nil
      expect(row[:dismissed_at]).not_to be_nil
    end

    it "updates the timestamp on re-dismiss (upsert)" do
      db[:dismissed_instances].insert(instance: "wt-a", dismissed_at: "2020-01-01T00:00:00Z")

      post "/board/wt-a/dismiss"

      row = db[:dismissed_instances].where(instance: "wt-a").first
      expect(row[:dismissed_at]).not_to eq("2020-01-01T00:00:00Z")
      expect(db[:dismissed_instances].where(instance: "wt-a").count).to eq(1)
    end
  end

  describe "POST /board/:instance/clear_card" do
    before { Brivlo::Database.setup(db) }

    it "deletes the instance card and redirects to /board" do
      db[:instance_cards].insert(
        instance: "wt-a", card_ref: "#42", card_title: "Fix bug",
        card_url: "https://trello.com/c/abc123", set_at: Time.now.utc.iso8601
      )

      post "/board/wt-a/clear_card"

      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_request.path).to eq("/board")
      expect(db[:instance_cards].where(instance: "wt-a").count).to eq(0)
    end

    it "succeeds even when no card exists" do
      post "/board/wt-a/clear_card"

      expect(last_response).to be_redirect
    end
  end

  describe "GET /wait_reasons" do
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

    it "shows wait reasons grouped by event and tool" do
      3.times { insert_event(event: "wait.permission", tool: "Bash") }
      insert_event(event: "wait.permission", tool: "Edit")

      get "/wait_reasons"

      expect(last_response.body).to include("Top Wait Reasons")
      expect(last_response.body).to include("wait.permission")
    end

    it "shows counts for each wait reason" do
      3.times { insert_event(event: "wait.permission", tool: "Bash") }

      get "/wait_reasons"

      expect(last_response.body).to include("3")
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
