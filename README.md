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
