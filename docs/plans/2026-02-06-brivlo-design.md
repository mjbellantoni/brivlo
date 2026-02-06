# Brivlo Design

A tiny control plane that stores and displays events from multiple Claude instances (worktrees) running on multiple hosts. Claude-agnostic: a separate repo handles Claude Code plugin wiring.

## Purpose

Show a dashboard of what every Claude instance is doing, especially when they're waiting for approval. Surface the most common wait reasons so permissions and skills can be refined over time.

## Project Structure

```
brivlo/
├── brivlo.gemspec
├── Gemfile
├── README.md
├── LICENSE.txt
├── bin/
│   ├── brivlo_event          # CLI sender
│   └── brivlo_server         # Sinatra server (WEBrick)
├── lib/
│   ├── brivlo.rb
│   └── brivlo/
│       ├── version.rb
│       ├── client.rb          # HTTP client logic (used by CLI)
│       ├── database.rb        # Sequel connection + schema setup
│       ├── server.rb          # Sinatra app
│       └── public/
│           └── style.css      # Dashboard stylesheet
├── spec/
│   ├── spec_helper.rb
│   └── brivlo/
│       ├── server_spec.rb     # Rack::Test for endpoints
│       ├── client_spec.rb     # Payload building, env, fail-open
│       └── database_spec.rb   # Schema creation, idempotency
└── db/                        # SQLite file lives here at runtime
```

Scaffolded with `bundle gem brivlo`. Structured as a gem (with `.gemspec`) for use across multiple projects via Gemfile git references. Not published to RubyGems.

## Dependencies

Runtime:
- sinatra
- sequel
- sqlite3

Development:
- rspec
- rack-test
- webmock
- factory_bot (if needed)

## Database

Single `events` table, auto-created on server boot via `Sequel.create_table?(:events)` (idempotent, no migration files).

```ruby
:event_id    String, primary_key: true  # UUID from client
:ts          String, null: false         # ISO8601 from client
:event       String, null: false         # e.g. "wait.permission", "task.start"
:instance    String, null: false         # e.g. "wt-a"
:host        String, null: false         # e.g. "mjb-dev-01"
:card        String, null: true
:skill       String, null: true
:tool        String, null: true
:summary     String, null: true
:meta        String, null: true          # JSON string
:received_at String, null: false         # server-side timestamp
```

Dedup: `event_id` is the primary key. `INSERT OR IGNORE` handles duplicates naturally.

## Endpoints

### GET /ping

Health check, no auth. Returns `200` with body `ok`.

### POST /events

Accepts JSON body. Requires `Authorization: Bearer <token>` validated against `ENV['BRIVLO_TOKEN']`.

- Missing/wrong token: `401`
- Valid: inserts event (INSERT OR IGNORE for dedup), returns `201`

### GET /board

The main UI. HTML dashboard, no auth. Auto-refreshes every 10 seconds via `<meta http-equiv="refresh" content="10">`. Served with a separate `style.css` stylesheet from `lib/brivlo/public/`.

**Top: Instance Status Table**

| Instance | Host | Status | Event | Card | Tool | Summary | Last Seen |
|----------|------|--------|-------|------|------|---------|-----------|
| wt-a | mjb-dev-01 | WAITING | wait.permission | 123 | Bash | Needs approval for git push | 12s ago |
| wt-b | mjb-dev-01 | active | task.start | 456 | -- | Implementing auth flow | 2m ago |

- Waiting rows visually distinct (bold/highlight) for quick scanning
- Relative timestamps ("12s ago", "5m ago") so staleness is obvious
- Sorted: waiting instances first, then by most recently seen
- Status logic: latest event matching `wait.*` => waiting, otherwise active

**Middle: Top Wait Reasons**

Aggregated from all `wait.*` events, grouped by `event` + `tool`:

| Reason | Tool | Count | Last Seen |
|--------|------|-------|-----------|
| wait.permission | Bash | 47 | 2m ago |
| wait.permission | Edit | 12 | 1h ago |
| wait.idle | -- | 8 | 30m ago |

Sorted by count descending. Tells you which permissions to refine.

**Bottom: Instance Detail Link**

### GET /board/:instance

Recent event history for a specific instance. Chronological list, last 50 events. Linked from the instance name in the status table.

## Client CLI

`bin/brivlo_event` — thin wrapper around `Brivlo::Client`.

```
brivlo_event <event> --instance wt-a --host mjb-dev-01 \
  --card 123 --skill brainstorming --tool Bash \
  --summary "Needs approval for git push" \
  --meta k=v --meta foo=bar
```

### Behavior

- Reads `BRIVLO_ENDPOINT` and `BRIVLO_TOKEN` from environment
- Generates `event_id` (SecureRandom.uuid) and `ts` (Time.now.utc.iso8601)
- POSTs JSON to `$BRIVLO_ENDPOINT/events`
- Uses `Net::HTTP` directly (no extra HTTP dependency)
- CLI parses args with `OptionParser`

### Fail-Open

- Timeout: 2 seconds (connect + read)
- On any error (timeout, connection refused, 5xx): warn to stderr, exit 0
- Missing `BRIVLO_ENDPOINT`: skip silently (exit 0) — safe to wire up when server isn't running
- Missing `BRIVLO_TOKEN`: warn to stderr, exit 0

## Auth

- `POST /events` requires `Authorization: Bearer $BRIVLO_TOKEN`
- Server validates against `ENV['BRIVLO_TOKEN']`
- All GET endpoints are unauthenticated

## Tests

### Server specs (Rack::Test)

- `GET /ping` returns 200 "ok"
- `POST /events` without token returns 401
- `POST /events` with valid token stores event, returns 201
- `POST /events` duplicate event_id doesn't create second row
- `GET /board` renders HTML with instance rows
- `GET /board` shows waiting instances with highlight
- `GET /board` shows top wait reasons section
- `GET /board/:instance` shows event history

### Client specs (WebMock)

- Builds correct JSON payload from arguments
- Sends Authorization header
- Generates UUID and timestamp
- On timeout: warns to stderr, exits 0
- On connection refused: warns to stderr, exits 0
- Missing BRIVLO_ENDPOINT: no-ops silently

### Database specs

- Creates table on first call
- Idempotent on repeated calls

All specs use in-memory SQLite (`sqlite:/`) for speed and isolation.

## Decisions

- **Sequel over ActiveRecord** — lightweight, appropriate for a standalone gem
- **WEBrick** — simplest server, no extra dependency
- **No `/instances` JSON endpoint** — YAGNI; `/board` computes state inline. Easy to extract later.
- **No migrations** — single `create_table?` call on boot, sufficient for v1
- **Synchronous HTTP** — fine for v1, fail-open ensures it doesn't block callers
- **Separate CSS file** — clean separation, served from `lib/brivlo/public/`
