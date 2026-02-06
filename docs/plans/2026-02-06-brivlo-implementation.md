# Brivlo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Ruby gem that collects events from multiple Claude instances and displays a live dashboard showing instance status and top wait reasons.

**Architecture:** Sinatra server with Sequel/SQLite stores events POSTed by a fail-open CLI client. A single HTML dashboard (`GET /board`) shows current instance status and aggregated wait reasons. No JSON API endpoints beyond event ingestion.

**Tech Stack:** Ruby 3.2, Sinatra, Sequel, SQLite3, WEBrick, RSpec, Rack::Test, WebMock

---

### Task 1: Project Setup — gemspec, dependencies, initial commit

**Files:**
- Modify: `brivlo.gemspec`
- Modify: `Gemfile`
- Modify: `.gitignore`
- Modify: `spec/brivlo_spec.rb`
- Modify: `lib/brivlo.rb`

**Step 1: Update the gemspec**

Replace `brivlo.gemspec` contents with:

```ruby
# frozen_string_literal: true

require_relative "lib/brivlo/version"

Gem::Specification.new do |spec|
  spec.name = "brivlo"
  spec.version = Brivlo::VERSION
  spec.authors = ["Matthew Bellantoni"]
  spec.email = ["mjbellantoni@gmail.com"]

  spec.summary = "Tiny control plane for monitoring Claude Code instances"
  spec.description = "Stores and displays events from multiple Claude instances across hosts"
  spec.homepage = "https://github.com/mjbellantoni/brivlo"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = %w[brivlo_event brivlo_server]
  spec.require_paths = ["lib"]

  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "sinatra", "~> 4.0"
  spec.add_dependency "sqlite3", "~> 2.0"
end
```

Note: removed `bin/` from the `start_with?` rejection list so `bin/brivlo_event` and `bin/brivlo_server` are included in gem files. The existing `bin/console` and `bin/setup` are dev tools and won't be installed as executables since they aren't in `spec.executables`.

**Step 2: Update the Gemfile**

Replace `Gemfile` contents with:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"
gem "rack-test", "~> 2.0"
gem "webmock", "~> 3.0"

gem "rubocop", "~> 1.21"
```

**Step 3: Update .gitignore**

Add to the end of `.gitignore`:

```
# SQLite databases
db/*.sqlite3
```

**Step 4: Fix the placeholder spec**

Replace `spec/brivlo_spec.rb` with:

```ruby
# frozen_string_literal: true

RSpec.describe Brivlo do
  it "has a version number" do
    expect(Brivlo::VERSION).not_to be_nil
  end
end
```

**Step 5: Clean up lib/brivlo.rb**

Replace `lib/brivlo.rb` with:

```ruby
# frozen_string_literal: true

require_relative "brivlo/version"

module Brivlo
  class Error < StandardError; end
end
```

**Step 6: Run bundle install**

Run: `bundle install`
Expected: Resolves and installs all dependencies successfully.

**Step 7: Run the spec to verify setup**

Run: `bundle exec rspec`
Expected: 1 example, 0 failures

**Step 8: Run rubocop**

Run: `bundle exec rubocop`
Expected: No offenses (or note any that need fixing)

**Step 9: Commit**

```bash
git add -A
git commit -m "Initial gem scaffold with dependencies

Sinatra, Sequel, SQLite3 for runtime.
RSpec, Rack::Test, WebMock for testing."
```

---

### Task 2: Database Layer

**Files:**
- Create: `lib/brivlo/database.rb`
- Create: `spec/brivlo/database_spec.rb`

**Step 1: Write the failing test**

Create `spec/brivlo/database_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "brivlo/database"

RSpec.describe Brivlo::Database do
  let(:db) { Sequel.sqlite }

  describe ".setup" do
    it "creates the events table" do
      described_class.setup(db)

      expect(db.tables).to include(:events)
    end

    it "is idempotent" do
      described_class.setup(db)
      described_class.setup(db)

      expect(db.tables).to include(:events)
    end

    it "creates all expected columns" do
      described_class.setup(db)

      columns = db.schema(:events).map(&:first)
      expect(columns).to eq(%i[event_id ts event instance host card skill tool summary meta received_at])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/brivlo/database_spec.rb`
Expected: FAIL — cannot load `brivlo/database`

**Step 3: Write minimal implementation**

Create `lib/brivlo/database.rb`:

```ruby
# frozen_string_literal: true

require "sequel"

module Brivlo
  module Database
    def self.setup(db)
      db.create_table?(:events) do
        String :event_id, primary_key: true
        String :ts, null: false
        String :event, null: false
        String :instance, null: false
        String :host, null: false
        String :card
        String :skill
        String :tool
        String :summary
        String :meta
        String :received_at, null: false
      end
    end

    def self.connect(path = nil)
      path ||= File.join(Dir.pwd, "db", "brivlo.sqlite3")
      FileUtils.mkdir_p(File.dirname(path))
      db = Sequel.sqlite(path)
      setup(db)
      db
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/brivlo/database_spec.rb`
Expected: 3 examples, 0 failures

**Step 5: Run rubocop**

Run: `bundle exec rubocop lib/brivlo/database.rb spec/brivlo/database_spec.rb`
Expected: No offenses

**Step 6: Commit**

```bash
git add lib/brivlo/database.rb spec/brivlo/database_spec.rb
git commit -m "Add database layer with events table schema"
```

---

### Task 3: Server — GET /ping

**Files:**
- Create: `lib/brivlo/server.rb`
- Create: `spec/brivlo/server_spec.rb`

**Step 1: Write the failing test**

Create `spec/brivlo/server_spec.rb`:

```ruby
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
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: FAIL — cannot load `brivlo/server`

**Step 3: Write minimal implementation**

Create `lib/brivlo/server.rb`:

```ruby
# frozen_string_literal: true

require "sinatra/base"
require_relative "database"

module Brivlo
  class Server < Sinatra::Base
    def initialize(db: nil)
      super()
      @db = db || Database.connect
      Database.setup(@db)
    end

    get "/ping" do
      "ok"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: 1 example, 0 failures

**Step 5: Commit**

```bash
git add lib/brivlo/server.rb spec/brivlo/server_spec.rb
git commit -m "Add Sinatra server with GET /ping"
```

---

### Task 4: Server — POST /events with auth and dedup

**Files:**
- Modify: `spec/brivlo/server_spec.rb`
- Modify: `lib/brivlo/server.rb`

**Step 1: Write the failing tests**

Add to `spec/brivlo/server_spec.rb` inside the `RSpec.describe` block:

```ruby
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
```

Also add `require "json"` at the top of the spec file.

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: 5 new failures

**Step 3: Implement POST /events with auth**

Add to `lib/brivlo/server.rb` inside the `Server` class:

```ruby
    before do
      if request.path == "/events" && request.request_method == "POST"
        token = ENV.fetch("BRIVLO_TOKEN", nil)
        provided = request.env["HTTP_AUTHORIZATION"]&.sub(/\ABearer\s+/, "")
        halt 401, "Unauthorized" unless token && provided == token
      end
    end

    post "/events" do
      request.body.rewind
      data = JSON.parse(request.body.read)

      fields = {
        event_id: data["event_id"],
        ts: data["ts"],
        event: data["event"],
        instance: data["instance"],
        host: data["host"],
        card: data["card"],
        skill: data["skill"],
        tool: data["tool"],
        summary: data["summary"],
        meta: data["meta"],
        received_at: Time.now.utc.iso8601
      }

      @db[:events].insert_ignore.insert(fields)
      status 201
      "ok"
    end
```

Add `require "json"` at the top of `lib/brivlo/server.rb`.

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: 6 examples, 0 failures

**Step 5: Commit**

```bash
git add lib/brivlo/server.rb spec/brivlo/server_spec.rb
git commit -m "Add POST /events with bearer auth and dedup"
```

---

### Task 5: Server — GET /board (instance status table)

**Files:**
- Modify: `spec/brivlo/server_spec.rb`
- Modify: `lib/brivlo/server.rb`

**Step 1: Write the failing tests**

Add to `spec/brivlo/server_spec.rb`:

```ruby
  describe "GET /board" do
    before do
      Database.setup(db)
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
  end
```

Add `require "securerandom"` at the top of the spec file.

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: New failures for GET /board tests

**Step 3: Implement GET /board**

Add a helper method and route to `lib/brivlo/server.rb`:

```ruby
    helpers do
      def relative_time(iso_string)
        return "—" unless iso_string

        seconds = Time.now.utc - Time.parse(iso_string)
        case seconds
        when 0...60 then "#{seconds.to_i}s ago"
        when 60...3600 then "#{(seconds / 60).to_i}m ago"
        when 3600...86_400 then "#{(seconds / 3600).to_i}h ago"
        else "#{(seconds / 86_400).to_i}d ago"
        end
      end

      def instance_status(event_name)
        event_name&.start_with?("wait.") ? "waiting" : "active"
      end
    end

    get "/board" do
      instances = @db[:events]
        .select_group(:instance)
        .select_append { max(ts).as(latest_ts) }
        .map do |row|
          latest = @db[:events]
            .where(instance: row[:instance], ts: row[:latest_ts])
            .first
          latest.merge(status: instance_status(latest[:event]))
        end
        .sort_by { |i| [i[:status] == "waiting" ? 0 : 1, i[:ts]] }
        .reverse_each.sort_by { |i| i[:status] == "waiting" ? 0 : 1 }

      content_type :html

      erb :board, locals: { instances: instances }, layout: :layout
    end
```

Create `lib/brivlo/views/layout.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="10">
  <title>Brivlo</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <h1>Brivlo</h1>
  <%= yield %>
</body>
</html>
```

Create `lib/brivlo/views/board.erb`:

```erb
<h2>Instances</h2>
<table>
  <thead>
    <tr>
      <th>Instance</th>
      <th>Host</th>
      <th>Status</th>
      <th>Event</th>
      <th>Card</th>
      <th>Tool</th>
      <th>Summary</th>
      <th>Last Seen</th>
    </tr>
  </thead>
  <tbody>
    <% instances.each do |inst| %>
      <tr class="<%= inst[:status] %>">
        <td><a href="/board/<%= inst[:instance] %>"><%= inst[:instance] %></a></td>
        <td><%= inst[:host] %></td>
        <td><%= inst[:status] %></td>
        <td><%= inst[:event] %></td>
        <td><%= inst[:card] %></td>
        <td><%= inst[:tool] %></td>
        <td><%= inst[:summary] %></td>
        <td><%= relative_time(inst[:ts]) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Set the views directory in the Server class:

```ruby
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")
```

Add `require "time"` at the top of server.rb.

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/brivlo/server.rb lib/brivlo/views/ spec/brivlo/server_spec.rb
git commit -m "Add GET /board with instance status table"
```

---

### Task 6: Server — GET /board (top wait reasons)

**Files:**
- Modify: `spec/brivlo/server_spec.rb`
- Modify: `lib/brivlo/server.rb`
- Modify: `lib/brivlo/views/board.erb`

**Step 1: Write the failing tests**

Add to the `GET /board` describe block in `spec/brivlo/server_spec.rb`:

```ruby
    describe "top wait reasons" do
      it "shows wait reasons grouped by event and tool" do
        3.times { insert_event(event: "wait.permission", tool: "Bash") }
        1.times { insert_event(event: "wait.permission", tool: "Edit") }

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
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: 2 new failures

**Step 3: Implement wait reasons query**

Add to the `get "/board"` route in `lib/brivlo/server.rb`, before the erb call:

```ruby
      wait_reasons = @db[:events]
        .where(Sequel.like(:event, "wait.%"))
        .select_group(:event, :tool)
        .select_append { count(*).as(count) }
        .select_append { max(ts).as(last_seen) }
        .order(Sequel.desc(:count))
        .all
```

Pass `wait_reasons` to the erb locals: `locals: { instances: instances, wait_reasons: wait_reasons }`

Add to `lib/brivlo/views/board.erb` after the instances table:

```erb
<h2>Top Wait Reasons</h2>
<table>
  <thead>
    <tr>
      <th>Reason</th>
      <th>Tool</th>
      <th>Count</th>
      <th>Last Seen</th>
    </tr>
  </thead>
  <tbody>
    <% wait_reasons.each do |wr| %>
      <tr>
        <td><%= wr[:event] %></td>
        <td><%= wr[:tool] || "—" %></td>
        <td><%= wr[:count] %></td>
        <td><%= relative_time(wr[:last_seen]) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/brivlo/server.rb lib/brivlo/views/board.erb spec/brivlo/server_spec.rb
git commit -m "Add top wait reasons to board"
```

---

### Task 7: Server — GET /board/:instance (event history)

**Files:**
- Modify: `spec/brivlo/server_spec.rb`
- Modify: `lib/brivlo/server.rb`
- Create: `lib/brivlo/views/instance.erb`

**Step 1: Write the failing tests**

Add to `spec/brivlo/server_spec.rb`:

```ruby
  describe "GET /board/:instance" do
    before { Database.setup(db) }

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
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: 3 new failures

**Step 3: Implement GET /board/:instance**

Add to `lib/brivlo/server.rb`:

```ruby
    get "/board/:instance" do
      instance = params[:instance]

      events = @db[:events]
        .where(instance: instance)
        .order(Sequel.desc(:ts))
        .limit(50)
        .all

      content_type :html
      erb :instance, locals: { instance: instance, events: events }, layout: :layout
    end
```

Create `lib/brivlo/views/instance.erb`:

```erb
<p><a href="/board">&larr; Back to board</a></p>
<h2><%= instance %></h2>
<table>
  <thead>
    <tr>
      <th>Time</th>
      <th>Event</th>
      <th>Host</th>
      <th>Card</th>
      <th>Skill</th>
      <th>Tool</th>
      <th>Summary</th>
    </tr>
  </thead>
  <tbody>
    <% events.each do |evt| %>
      <tr class="<%= evt[:event]&.start_with?('wait.') ? 'waiting' : '' %>">
        <td><%= relative_time(evt[:ts]) %></td>
        <td><%= evt[:event] %></td>
        <td><%= evt[:host] %></td>
        <td><%= evt[:card] %></td>
        <td><%= evt[:skill] %></td>
        <td><%= evt[:tool] %></td>
        <td><%= evt[:summary] %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/brivlo/server.rb lib/brivlo/views/instance.erb spec/brivlo/server_spec.rb
git commit -m "Add GET /board/:instance event history"
```

---

### Task 8: CSS Stylesheet

**Files:**
- Create: `lib/brivlo/public/style.css`

**Step 1: Create the stylesheet**

Create `lib/brivlo/public/style.css`:

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace;
  background: #1a1a2e;
  color: #e0e0e0;
  padding: 2rem;
  line-height: 1.5;
}

h1 {
  color: #e94560;
  margin-bottom: 0.5rem;
  font-size: 1.5rem;
}

h2 {
  color: #8a8a9a;
  margin: 1.5rem 0 0.75rem;
  font-size: 1.1rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

a {
  color: #4ea8de;
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 1.5rem;
}

th {
  text-align: left;
  padding: 0.5rem 0.75rem;
  border-bottom: 2px solid #2a2a4a;
  color: #8a8a9a;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

td {
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid #2a2a4a;
  font-size: 0.9rem;
}

tr.waiting {
  background: #2a1a1a;
}

tr.waiting td {
  color: #e94560;
  font-weight: 600;
}

tr.active td {
  color: #4ade80;
}

p {
  margin-bottom: 0.5rem;
}
```

**Step 2: Verify the stylesheet is served**

Run: `bundle exec rspec spec/brivlo/server_spec.rb`
Expected: All existing tests still pass

**Step 3: Commit**

```bash
git add lib/brivlo/public/style.css
git commit -m "Add dashboard stylesheet"
```

---

### Task 9: Client Library

**Files:**
- Create: `lib/brivlo/client.rb`
- Create: `spec/brivlo/client_spec.rb`

**Step 1: Write the failing tests**

Create `spec/brivlo/client_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "json"
require "brivlo/client"

RSpec.describe Brivlo::Client do
  let(:endpoint) { "http://localhost:9292" }
  let(:token) { "test-token" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("BRIVLO_ENDPOINT", nil).and_return(endpoint)
    allow(ENV).to receive(:fetch).with("BRIVLO_TOKEN", nil).and_return(token)
  end

  describe "#send_event" do
    it "posts JSON to the endpoint" do
      stub = stub_request(:post, "#{endpoint}/events")
        .with(
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{token}"
          }
        )
        .to_return(status: 201, body: "ok")

      client = described_class.new
      client.send_event(
        event: "wait.permission",
        instance: "wt-a",
        host: "mjb-dev-01"
      )

      expect(stub).to have_been_requested
    end

    it "includes event_id and ts in payload" do
      stub_request(:post, "#{endpoint}/events").to_return(status: 201)

      client = described_class.new
      client.send_event(event: "task.start", instance: "wt-a", host: "dev-01")

      expect(WebMock).to have_requested(:post, "#{endpoint}/events")
        .with { |req|
          body = JSON.parse(req.body)
          body["event_id"] =~ /\A[0-9a-f-]{36}\z/ && body["ts"] =~ /\d{4}-\d{2}-\d{2}T/
        }
    end

    it "includes optional fields in payload" do
      stub_request(:post, "#{endpoint}/events").to_return(status: 201)

      client = described_class.new
      client.send_event(
        event: "wait.permission",
        instance: "wt-a",
        host: "dev-01",
        card: "123",
        skill: "brainstorming",
        tool: "Bash",
        summary: "Needs approval",
        meta: { "foo" => "bar" }
      )

      expect(WebMock).to have_requested(:post, "#{endpoint}/events")
        .with { |req|
          body = JSON.parse(req.body)
          body["card"] == "123" &&
            body["tool"] == "Bash" &&
            body["meta"] == '{"foo":"bar"}'
        }
    end

    it "no-ops silently when BRIVLO_ENDPOINT is not set" do
      allow(ENV).to receive(:fetch).with("BRIVLO_ENDPOINT", nil).and_return(nil)

      client = described_class.new

      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .not_to raise_error
    end

    it "warns to stderr and exits cleanly on connection failure" do
      stub_request(:post, "#{endpoint}/events").to_raise(Errno::ECONNREFUSED)

      client = described_class.new

      expect($stderr).to receive(:puts).with(/brivlo/i)
      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .not_to raise_error
    end

    it "warns to stderr and exits cleanly on timeout" do
      stub_request(:post, "#{endpoint}/events").to_timeout

      client = described_class.new

      expect($stderr).to receive(:puts).with(/brivlo/i)
      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .not_to raise_error
    end

    it "warns when BRIVLO_TOKEN is not set" do
      allow(ENV).to receive(:fetch).with("BRIVLO_TOKEN", nil).and_return(nil)

      client = described_class.new

      expect($stderr).to receive(:puts).with(/BRIVLO_TOKEN/i)
      client.send_event(event: "task.start", instance: "wt-a", host: "dev")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/brivlo/client_spec.rb`
Expected: FAIL — cannot load `brivlo/client`

**Step 3: Write the implementation**

Create `lib/brivlo/client.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "uri"
require "time"

module Brivlo
  class Client
    TIMEOUT = 2

    def initialize
      @endpoint = ENV.fetch("BRIVLO_ENDPOINT", nil)
      @token = ENV.fetch("BRIVLO_TOKEN", nil)
    end

    def send_event(event:, instance:, host:, **optional)
      return unless @endpoint

      unless @token
        $stderr.puts "[brivlo] BRIVLO_TOKEN not set, skipping event"
        return
      end

      payload = {
        event_id: SecureRandom.uuid,
        ts: Time.now.utc.iso8601,
        event: event,
        instance: instance,
        host: host,
        card: optional[:card],
        skill: optional[:skill],
        tool: optional[:tool],
        summary: optional[:summary],
        meta: optional[:meta]&.to_json
      }.compact

      post(payload)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      $stderr.puts "[brivlo] Failed to send event: #{e.message}"
    end

    private

    def post(payload)
      uri = URI.join(@endpoint, "/events")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@token}"
      request.body = JSON.generate(payload)

      http.request(request)
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/brivlo/client_spec.rb`
Expected: 7 examples, 0 failures

**Step 5: Commit**

```bash
git add lib/brivlo/client.rb spec/brivlo/client_spec.rb
git commit -m "Add fail-open client library"
```

---

### Task 10: CLI Executables

**Files:**
- Create: `bin/brivlo_event`
- Create: `bin/brivlo_server`

**Step 1: Create bin/brivlo_event**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "brivlo/client"

options = {}
meta = {}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: brivlo_event <event> [options]"

  opts.on("--instance INSTANCE", "Instance name (e.g. wt-a)") { |v| options[:instance] = v }
  opts.on("--host HOST", "Host name") { |v| options[:host] = v }
  opts.on("--card CARD", "Card/ticket number") { |v| options[:card] = v }
  opts.on("--skill SKILL", "Skill name") { |v| options[:skill] = v }
  opts.on("--tool TOOL", "Tool name") { |v| options[:tool] = v }
  opts.on("--summary SUMMARY", "Event summary") { |v| options[:summary] = v }
  opts.on("--meta K=V", "Metadata key=value (repeatable)") do |v|
    key, value = v.split("=", 2)
    meta[key] = value
  end
end

parser.parse!

event = ARGV.shift

unless event
  $stderr.puts parser.help
  exit 1
end

unless options[:instance] && options[:host]
  $stderr.puts "Error: --instance and --host are required"
  $stderr.puts parser.help
  exit 1
end

options[:meta] = meta unless meta.empty?

client = Brivlo::Client.new
client.send_event(event: event, **options)
```

**Step 2: Create bin/brivlo_server**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "brivlo/server"

port = Integer(ENV.fetch("PORT", 9292))
db_path = ENV.fetch("BRIVLO_DB", File.join(Dir.pwd, "db", "brivlo.sqlite3"))

puts "Starting Brivlo server on port #{port}..."
puts "Database: #{db_path}"

db = Brivlo::Database.connect(db_path)
app = Brivlo::Server.new(db: db)

app.run!(port: port, server: "webrick")
```

**Step 3: Make executables**

Run: `chmod +x bin/brivlo_event bin/brivlo_server`

**Step 4: Verify the executables parse correctly**

Run: `ruby -c bin/brivlo_event && ruby -c bin/brivlo_server`
Expected: `Syntax OK` for both

**Step 5: Commit**

```bash
git add bin/brivlo_event bin/brivlo_server
git commit -m "Add CLI executables"
```

---

### Task 11: README and final cleanup

**Files:**
- Modify: `README.md`
- Modify: `lib/brivlo.rb`

**Step 1: Update README.md**

Replace `README.md` with:

```markdown
# Brivlo

Tiny control plane for monitoring Claude Code instances across hosts. Collects events and displays a live dashboard showing instance status and top wait reasons.

## Setup

```bash
gem build brivlo.gemspec
gem install brivlo-0.1.0.gem
```

Or add to your Gemfile:

```ruby
gem "brivlo", git: "https://github.com/mjbellantoni/brivlo"
```

## Server

```bash
export BRIVLO_TOKEN=your-secret-token
export PORT=9292                    # optional, default 9292
export BRIVLO_DB=db/brivlo.sqlite3  # optional

brivlo_server
```

Open http://localhost:9292/board to view the dashboard.

## Client

```bash
export BRIVLO_ENDPOINT=http://localhost:9292
export BRIVLO_TOKEN=your-secret-token

brivlo_event wait.permission \
  --instance wt-a \
  --host mjb-dev-01 \
  --card 123 \
  --tool Bash \
  --summary "Needs approval for git push" \
  --meta reason=destructive
```

The client fails open: if the server is unreachable, it warns to stderr and exits 0.

## Endpoints

- `GET /ping` — health check
- `POST /events` — store an event (bearer auth required)
- `GET /board` — live dashboard (auto-refreshes every 10s)
- `GET /board/:instance` — event history for an instance

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```
```

**Step 2: Update lib/brivlo.rb to require submodules**

```ruby
# frozen_string_literal: true

require_relative "brivlo/version"

module Brivlo
  class Error < StandardError; end
end
```

(No change needed — keep it minimal. Each component is required individually.)

**Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

**Step 4: Run rubocop**

Run: `bundle exec rubocop`
Expected: No offenses (fix any that appear)

**Step 5: Commit**

```bash
git add README.md
git commit -m "Add README with setup and usage docs"
```

---

## Verification

After all tasks complete:

1. `bundle exec rspec` — all green
2. `bundle exec rubocop` — no offenses
3. `bin/brivlo_server` — starts on port 9292
4. Visit `http://localhost:9292/ping` — returns "ok"
5. `BRIVLO_ENDPOINT=http://localhost:9292 BRIVLO_TOKEN=... bin/brivlo_event wait.permission --instance wt-a --host dev-01 --tool Bash --summary "test"`
6. Visit `http://localhost:9292/board` — shows the event