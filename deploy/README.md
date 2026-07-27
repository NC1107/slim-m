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
docker compose up -d
```

The server image tracks the rolling `latest` tag.
Set `SLIMM_VERSION` in `.env` to a published release (see the [releases page](https://github.com/NC1107/slim-m/releases)) to freeze it on a specific version instead.

`LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` have no defaults, on purpose.
They authorize minting a room token, so a placeholder default would be a publicly known credential on a publicly reachable SFU.
Compose refuses to start until both are set and tells you which one is missing; generate a pair with `docker run --rm livekit/livekit-server:v1.10.1 generate-keys`.

Check it:

```bash
curl https://<SLIMM_API_DOMAIN>/healthz   # -> ok
docker compose ps                         # server and caddy should show healthy
```

## Backups (optional)

Litestream is off by default because it needs a real S3-compatible bucket.
To turn it on: fill in the `LITESTREAM_*` values in `.env`, uncomment `COMPOSE_PROFILES=litestream`, then re-run `docker compose up -d`.

**Litestream replicates only the SQLite database file. Attachment and avatar bytes are not covered.**
They live on disk beside the database, at `SLIMM_ATTACHMENTS_DIR` (default `/data/media` inside the container, so the same `slimm_data` volume as the database), specifically because multi-megabyte blobs in the SQLite file would bloat what Litestream streams for no benefit.
That means restoring from a Litestream replica brings back every message and its attachment references, but not the attachment files themselves; a client would render broken images and failed downloads for anything uploaded since the last time `/data/media` was backed up some other way.
If attachments matter to your deployment, back up the whole `slimm_data` volume yourself (a periodic `docker run --rm -v slimm_data:/data -v $(pwd):/backup alpine tar czf /backup/slimm-data-$(date +%F).tgz -C / data`, restic, or your platform's volume-snapshot feature), not just the database.

## Browser clients (`SLIMM_CORS_ALLOWED_ORIGINS`)

Empty by default, and that default is the safe one: with nothing set there is no CORS layer at all, and a browser on any other origin is refused.
The desktop and mobile clients send no `Origin` header, so this setting has no effect on them whatsoever.
You only need it if you serve a web build of the client from a different origin than the API.

```
SLIMM_CORS_ALLOWED_ORIGINS=https://app.example.com,http://localhost:8099
```

Deny-by-default matters more here than it looks, and not only for a server on the public internet.
A self-host usually sits on a network your own browser can route to and the rest of the internet cannot.
An open policy would hand every page you happen to visit the ability to drive that deployment from inside the perimeter its network position was protecting it with, using your browser as the way in.
That is why `*` is refused outright rather than accepted as a shortcut, and why the list is exact origins you write down.

Malformed entries stop the server at startup with the offending value named, rather than turning into a `blocked by CORS policy` line in a browser console days later.
An origin is `scheme://host[:port]` and nothing more, so a path, a query, a fragment, or embedded credentials are all rejected.
A default port, an uppercase host, a unicode host, and a bare trailing slash are all normalized to the form a browser actually sends, so those still match.

Credentials are never allowed, whatever you set.
slim-m authenticates with an `Authorization: Bearer` header the client attaches itself; browsers never send that automatically the way they send cookies.
Credentialed mode would therefore buy nothing here while adding the ambient authority that turns one mistaken origin into a full account takeover, so the server does not send `Access-Control-Allow-Credentials` at all.

Only `authorization` and `content-type` are accepted as request headers, and only the methods the API actually serves (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) are allowed.
Preflights are answered by the server itself and cached for ten minutes.

## Voice and screen share

LiveKit's signaling channel is fronted by Caddy on the `LIVEKIT_DOMAIN` you set, so no extra port beyond 443 is needed for a client to negotiate a call.
Carrying the call is separate, and needs four things open at your router or cloud firewall on top of that.
Docker publishes all of them; a firewall in front of Docker does not know that.

| From `.env` | Default | Carries |
| --- | --- | --- |
| `LIVEKIT_UDP_PORT_START`-`LIVEKIT_UDP_PORT_END` | 50000-50100/udp | Call media. The path almost every call actually takes. |
| `LIVEKIT_TURN_RELAY_PORT_START`-`LIVEKIT_TURN_RELAY_PORT_END` | 30000-30100/udp | TURN's relay ports, a separate block from the media range. |
| `LIVEKIT_TURN_UDP_PORT` | 3478/udp | STUN and TURN itself, for clients whose NAT will not do better. |
| `LIVEKIT_TCP_PORT` | 7881/tcp | The fallback for a client that cannot send UDP at all. |

Leaving the TURN relay range closed is worse than having no TURN at all: LiveKit keeps advertising relay candidates and every one of them times out, so calls that would have failed fast instead hang.

Move any of these if something on the host already holds the port.
A UniFi controller publishes 3478 for its own STUN, and a second SFU on the same box already holds 7881.
Both sides of each mapping follow the variable, so changing it in `.env` is enough.

TURN/TLS, for clients on networks that allow nothing but outbound 443, is off by default and documented in `docker-compose.yml`.

If LiveKit exits at startup with `could not resolve external IP`, that is your host's DNS, not your firewall.
Ubuntu and Fedora run systemd-resolved, whose `/etc/resolv.conf` names a `127.0.0.53` stub that does not exist inside a container, and LiveKit needs one hostname resolved to discover the address peers must reach it on.
The `dns:` block on the livekit service is there for this; point it at whichever resolvers you prefer.

## Files

- `docker-compose.yml` (repository root) - the stack itself.
- `deploy/Caddyfile` - routes the API domain and LiveKit's signaling domain through Caddy, terminating TLS.
- `deploy/.env.example` - every variable the compose file reads, with safe defaults and comments.

## Upgrading

Bump the pinned image tag in `docker-compose.yml` (server, Caddy, LiveKit, or Litestream) and run `docker compose up -d` again.
The named volumes (`slimm_data`, `caddy_data`, `caddy_config`) are untouched by an image swap.
