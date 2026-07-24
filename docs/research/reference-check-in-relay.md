# check-in-relay: Technical Summary

## Purpose

check-in-relay is a small Go service that solves a specific self-hosting problem for the Check-In app (https://github.com/NC1107/check-in).
Check-In's published mobile apps are built against the maintainer's Firebase project, so every installed app mints its FCM token against that project.
A self-hoster who points their own server at their own Firebase credentials gets `SENDER_ID_MISMATCH` on every push, because the token and the credentials belong to different Firebase projects.
The maintainer cannot simply hand out the Firebase service-account JSON either, since that credential can push to any Check-In device on any server, making it a master key rather than a per-host one.

The relay is the fix.
The maintainer runs a single instance that holds the one Firebase service account.
Each self-hosted Check-In server registers with the relay once on first boot, receives a scoped and revocable key, and from then on sends its notifications to the relay instead of directly to FCM.
Self-hosters get working push against the maintainer's Firebase project, and nobody but the maintainer ever holds the underlying credential.

The relay is deliberately minimal in what it sees and stores.
It only receives a notification title, body, a small data payload (notification type and post id), and the device tokens to send to.
It never sees post content, photos, comments, phone numbers, or group membership.
It does not log tokens or notification text, only counts and error/status codes.

## Architecture

The codebase is a single Go module (`github.com/nc1107/check-in-relay`, Go 1.26) built as one static binary with CGO disabled, so the container image has no shell, no libc dependency, and no external database process to run.

Layout:
- `cmd/relay/main.go`: process entrypoint.
  Loads config, reads the FCM credentials file, opens the SQLite key store, wires up the HTTP server, and handles graceful shutdown on SIGINT/SIGTERM.
  Also implements a `-healthcheck` subcommand that hits the local `/healthz` endpoint and exits 0/1, used as the Docker healthcheck since the distroless base image has no curl or shell.
- `internal/config`: reads all runtime settings from environment variables with sane defaults for a single maintainer-run relay.
- `internal/api`: the HTTP layer.
  - `server.go` builds the `Server` struct (config, FCM sender, key store, two rate limiters) and the `net/http` mux, using Go 1.22+ method+path routing patterns so the project needs no router dependency.
  - `register.go` implements `POST /v1/register`.
  - `send.go` implements `POST /v1/send`.
  - `admin.go` implements the token-gated `/admin/keys` endpoints.
  - `helpers.go` has small shared utilities: JSON helpers, bearer-token extraction, client-IP resolution from `X-Forwarded-For`, a panic-recovery middleware, and result tallying for log lines.
- `internal/keys`: the SQLite-backed key store (issue, verify, list, revoke).
- `internal/fcm`: a direct REST client for FCM HTTP v1, independent of the Firebase Admin SDK.
- `internal/ratelimit`: an in-memory token-bucket rate limiter keyed by an arbitrary string (client IP or key id).

The FCM client is a deliberate copy of the equivalent send path in the main Check-In server's `internal/push` package.
Go does not allow importing another module's `internal/` package, and keeping an independent copy keeps the relay decoupled from the main server's release cycle.
The one addition here is a per-token `Result`, so callers can prune tokens FCM reports as dead.

## HTTP API Surface

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/v1/register` | none (IP rate-limited) | Mints a new key. Optional JSON body `{"publicUrl": "..."}` is stored, unverified, purely as an admin-facing label. Returns `{"key": "..."}` once; the plaintext is never recoverable afterward. |
| `POST` | `/v1/send` | `Authorization: Bearer <key>` | Forwards `{"messages": [{"token","title","body","data"}]}` to FCM. Returns `{"results": [{"token","status"}]}`, where status is `delivered`, `unregistered`, or `error`. |
| `GET` | `/healthz` | none | Liveness probe, also used by the container healthcheck. |
| `GET` | `/admin/keys` | `Authorization: Bearer <admin token>` | Lists all issued keys (metadata only: id, label, created/last-used/revoked timestamps; never the secret or its hash). |
| `POST` | `/admin/keys/{id}/revoke` | `Authorization: Bearer <admin token>` | Revokes a key by id so a misbehaving server can be cut off. |

All request bodies are decoded with `DisallowUnknownFields` and a byte cap (4 KiB for register, 1 MiB for send), and every handler is wrapped in a panic-recovery middleware that converts a panic into a 500 instead of crashing the process.
`/v1/send` also enforces `RELAY_MAX_MESSAGES` (default 500) as an upper bound on device tokens per request, and drops messages with an empty token before forwarding.

## Key Design Decisions

**Scoped, per-server keys.**
Each self-hosted Check-In server gets its own key rather than sharing the maintainer's Firebase credential.
A key only grants the ability to POST to `/v1/send`; it cannot read other servers' data and carries no access to the Firebase project itself.
This bounds the blast radius of a single compromised or misbehaving self-hosted server to that server's own key, which the maintainer can revoke without affecting anyone else.

**SHA-256 hashed keys in SQLite.**
The store (`internal/keys`) never persists the plaintext key, only `sha256(key)` as a hex string in a `key_hash` column with a UNIQUE constraint.
The plaintext (`ckr_` prefix plus 32 random bytes, base64url-encoded) is returned exactly once at issuance and is unrecoverable after that; a leak of the SQLite file yields nothing directly usable.
Verification re-hashes the presented bearer token and does an indexed lookup, so verification cost does not depend on the number of issued keys.
SQLite itself is the pure-Go `modernc.org/sqlite` driver, which is why the binary can be built with `CGO_ENABLED=0` and stay a single static file with no system SQLite library dependency.
The store opens with `busy_timeout`, WAL journaling, and `temp_store=MEMORY` (the last because the distroless runtime has no writable temp directory), and caps the connection pool at one connection, since modernc/sqlite serializes writes on a single connection cleanly and a small relay has no need for extra coordination.

**Per-IP and per-key rate limiting.**
`internal/ratelimit` is a small in-memory token-bucket limiter keyed by an arbitrary string.
Registration (`/v1/register`) is limited per client IP (`RELAY_REGISTER_PER_HOUR`, default 5, burst `RELAY_REGISTER_BURST`, default 3), which bounds mass key-minting from a single source.
Sending (`/v1/send`) is limited per key id (`RELAY_SEND_PER_MINUTE`, default 120, burst `RELAY_SEND_BURST`, default 60), which bounds how hard one registered server can hammer FCM through the relay regardless of source IP.
Idle buckets are swept on a 10-minute cutoff, checked opportunistically every 5 minutes of wall-clock activity, so the limiter's memory footprint stays bounded on an otherwise-idle relay.
The limiter is explicitly documented as sufficient only for a single-instance relay; a multi-instance deployment would need to move this state to a shared store (Redis or similar).

**Admin endpoints.**
`/admin/keys` and `/admin/keys/{id}/revoke` are gated by a single shared bearer token (`RELAY_ADMIN_TOKEN`), compared in constant time via `crypto/subtle` to avoid timing side channels.
The admin routes are only registered on the mux at all when the token is set; if it is empty, the endpoints do not exist rather than existing and rejecting every request, which keeps an accidental misconfiguration from silently opening an admin surface with an empty-string token.
The list endpoint returns metadata only, never the secret or its hash, so even an admin cannot recover a lost plaintext key; the only remedy for a lost key is re-registration.

**Caddy TLS.**
The default `docker-compose.yml` runs a Caddy reverse proxy in front of the relay container, configured by a single-line `Caddyfile` that reverse-proxies `{$RELAY_DOMAIN}` to `relay:8090`.
Caddy automatically obtains and renews a Let's Encrypt certificate for `RELAY_DOMAIN`, so a self-hoster only needs to point DNS at the host and set two environment variables to get working HTTPS with no manual certificate handling.
The README documents an explicit alternative for hosts that already run Traefik or another reverse proxy: drop the `caddy` service and route directly to the relay container's port 8090.
Because the relay always expects to sit behind a trusted reverse proxy, `clientIP()` trusts `X-Forwarded-For` (taking the first hop) for the per-IP rate limiter, falling back to the raw socket address only when the header is absent.

## Operational Model

The relay is designed to be run by exactly one maintainer, for many self-hosted Check-In servers, as a small always-on service.
Deployment is `docker compose up -d` with two prerequisites: a `.env` file setting `RELAY_DOMAIN` and `RELAY_ADMIN_TOKEN`, and the Firebase service-account JSON mounted into the container.
The build is a two-stage Dockerfile: `golang:1.26-alpine` compiles a static binary (`CGO_ENABLED=0`, trimmed and stripped), and the runtime image is `gcr.io/distroless/static-debian12:nonroot`, running as a non-root UID with no shell, package manager, or curl available inside the container.
The data directory is pre-created and chowned to the nonroot UID at build time, because Docker seeds a freshly created named volume from the image's contents and permissions at that path, and the runtime image otherwise has no tooling available to fix ownership after the fact.

State is a single SQLite file on a named Docker volume (`relay_data`), holding only the `keys` table (hashed key, label, timestamps).
There is no separate database service to operate, back up, or upgrade.
The README calls out explicitly that losing this volume means every previously registered server must re-register on its next boot; it is the one piece of state that matters operationally.

Both services (relay and Caddy) declare a 128 MB memory limit in `docker-compose.yml`, consistent with a lightweight, low-traffic relay.
The relay logs operational counts (issued key labels, per-request delivered/unregistered/error tallies keyed by key id) but never tokens or message content, matching the "what the relay sees" privacy commitment in the README.
Configuration is entirely environment-variable driven (`RELAY_HTTP_ADDR`, `RELAY_FCM_CREDENTIALS_FILE`, `RELAY_DB_PATH`, `RELAY_ADMIN_TOKEN`, the four rate-limit knobs, `RELAY_MAX_MESSAGES`), which keeps the service a single self-contained binary appropriate for a maintainer running it as a side project rather than a managed platform.

## What Would Need to Change for a Full Messaging App

The relay's current shape is intentionally narrow: one credential, one push channel (FCM, which also reaches iOS through APNs indirectly), infrequent registration, and bursty but bounded notification volume tied to a check-in style app.
Serving a full messaging app would put pressure on several of these assumptions.

**APNs alongside FCM.**
Today iOS delivery goes through FCM's APNs bridge, which works but adds latency and an extra point of failure, and limits access to APNs-specific features (interruption levels, communication notifications, richer push payloads).
A messaging app would likely want a direct APNs HTTP/2 provider path alongside FCM, which means: a second credential type in `internal/config` and `main.go` (an APNs auth key or certificate, not just the Firebase JSON), a new `internal/apns` package mirroring `internal/fcm`'s shape (`Message`, `Result`, `Sender.Send`), a way for `/v1/send` to route each message by platform (either an explicit `platform` field per message or by token shape/registration metadata), and a unified `Result`/status mapping since APNs and FCM report deliverability differently (APNs' `410`/`BadDeviceToken` versus FCM's `UNREGISTERED`). The scoped-key model extends cleanly here since a key would just be authorized to send through both channels; the harder part is credential management, since APNs keys are typically per-app and can expire, unlike a long-lived Firebase service account.

**Wake-up pushes.**
Check-in style notifications are user-visible by design.
A messaging app needs silent/background wake-up pushes (FCM data-only messages, APNs content-available background pushes) to trigger a client to fetch new messages, refresh a socket connection, or update local state without alerting the user.
This changes the message schema (a `silent`/`background` flag or a distinct message type, since these have different payload shape and priority requirements on both FCM and APNs), changes rate-limiting economics (background pushes are typically far higher volume, one per new message or per active conversation rather than one per notable event), and changes what "delivered" means for logging and metrics, since these pushes are invisible to the end user and only observable through delivery telemetry.

**Device-to-server association.**
The current model is server-to-relay: a Check-In server registers once and gets one key used for all its notifications, with no concept of individual devices at the relay layer, since device tokens live in the calling server's own database and only pass through per `/v1/send` call.
A messaging app typically needs the reverse or an additional layer: multiple devices per user, multiple users per server, and potentially per-device delivery preferences (which conversations, mute state, badge counts) that the relay would need visibility into to do anything beyond blind forwarding.
If the relay stays a dumb forwarder (the current design's strength), this may not need to change at all, since device-to-user mapping can stay entirely in the calling server's domain and the relay keeps only opaque tokens; scaling to a messaging app would only require this if the relay itself takes on responsibilities like fan-out to a device list, deduplication, or badge-count computation, which would need a new `devices` or `subscriptions` concept in `internal/keys` or a sibling package, and a materially larger SQLite schema (or migration to Postgres, see below).

**Higher volume.**
Several current design choices assume low, bursty traffic from a small number of self-hosted servers, and would need to change under sustained messaging-app volume:
- The in-memory rate limiter (`internal/ratelimit`) is explicitly single-instance only; scaling the relay horizontally (needed once volume exceeds what one process can handle) requires moving bucket state to a shared store such as Redis, or switching to a sharding/consistent-hashing scheme per key.
- SQLite with `SetMaxOpenConns(1)` is a deliberate simplicity choice for a low-write workload (key issuance and revocation, occasional last-used-at updates); a messaging app with much higher key/session churn or a devices table would likely outgrow single-writer SQLite and want Postgres or another server-based database, both for write concurrency and for running the relay as multiple replicas behind a load balancer.
- The synchronous, one-request-per-token `Sender.Send` loop in `internal/fcm` (and the equivalent APNs client) does not batch or parallelize; at messaging-app volumes this would need concurrent sends with bounded parallelism, and likely a queue (in-process worker pool at minimum, or an external queue like SQS/NATS at higher scale) so `/v1/send` can return quickly and retries/backoff can be handled asynchronously rather than holding the HTTP request open for the full FCM/APNs round trip.
- `WriteTimeout: 60s` on the HTTP server and the synchronous send path together mean a large batch could hold a connection open for a long time; decoupling accept-and-queue from actual delivery would be necessary once message volume or batch sizes grow.
- The current 128 MB memory limit and single-container deployment model (Docker Compose on one host) would need to become a horizontally scaled deployment (multiple relay replicas behind Caddy or a load balancer, shared rate-limit and database state) to handle messaging-app-scale concurrent connections and throughput.
