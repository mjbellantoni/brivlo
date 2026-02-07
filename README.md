# Brivlo

Tiny control plane for monitoring Claude Code instances across hosts. Collects events and displays a live dashboard showing instance status and top wait reasons.

## Configuration

Create `.brivlo.yml` in the project directory or `~/.brivlo.yml`:

```yaml
BRIVLO_ENDPOINT: https://your-subdomain.ngrok-free.app
BRIVLO_TOKEN: your-secret-token
```

Project file takes priority over home. Environment variables override file values.

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
brivlo_server
```

Optional env overrides: `PORT` (default 9292), `BRIVLO_DB` (default `db/brivlo.sqlite3`).

Open http://localhost:9292/board to view the dashboard.

To expose via ngrok:

```bash
bin/brivlo_ngrok
```

## Client

```bash
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
