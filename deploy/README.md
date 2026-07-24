# Self-hosting slim-m

A minimal production stack for a friend group.
It wires up the slim-m server, Caddy for automatic TLS, LiveKit for voice and screen share, and an optional Litestream sidecar that streams the SQLite database to S3-compatible storage.

## Prerequisites

- A host (a VPS, or a box at home with a public IP) with Docker and the Docker Compose plugin installed.
- Two DNS records pointed at that host: one for the slim-m API domain, one for LiveKit's signaling domain.
- Ports 80 and 443 (TCP and UDP) reachable from the internet, plus the UDP media range you choose in `.env`.

## One-command walkthrough

```bash
git clone https://github.com/NC1107/slim-m.git
cd slim-m
cp deploy/.env.example .env
# edit .env: both domains, ACME_EMAIL, and a real LIVEKIT_API_KEY/SECRET
# set the server image tag in docker-compose.yml to a published release
# (no image is published to GHCR until the first release is cut)
docker compose up -d
```

Check it:

```bash
curl https://<SLIMM_API_DOMAIN>/healthz   # -> ok
docker compose ps                         # server and caddy should show healthy
```

## Backups (optional)

Litestream is off by default because it needs a real S3-compatible bucket.
To turn it on: fill in the `LITESTREAM_*` values in `.env`, uncomment `COMPOSE_PROFILES=litestream`, then re-run `docker compose up -d`.

## Voice and screen share

LiveKit's signaling channel is fronted by Caddy on the `LIVEKIT_DOMAIN` you set, so no extra port beyond 443 is needed for clients to connect.
Call media itself is separate: it needs the UDP port range from `.env` open at your firewall, and TURN/TLS (for clients on very restrictive networks) is off by default and documented in `docker-compose.yml` if you need it.

## Files

- `docker-compose.yml` (repository root) - the stack itself.
- `deploy/Caddyfile` - routes the API domain and LiveKit's signaling domain through Caddy, terminating TLS.
- `deploy/.env.example` - every variable the compose file reads, with safe defaults and comments.

## Upgrading

Bump the pinned image tag in `docker-compose.yml` (server, Caddy, LiveKit, or Litestream) and run `docker compose up -d` again.
The named volumes (`slimm_data`, `caddy_data`, `caddy_config`) are untouched by an image swap.
