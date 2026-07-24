# Backend and Server Architecture

Status: pre-implementation research.
Scope: language and framework choice, module boundaries, API style, auth surface, config, admin/moderation APIs, observability, extensibility, deployment weight, testing strategy, and idle resource targets.

## 1. Language and framework: two services, two verdicts

The brief describes two different server-shaped things: the main chat server and the push relay.
They have different jobs and should not be forced into one language.

**Main server: Rust, Axum, SQLx, PostgreSQL.**
This repeats echo-messenger's stack, deliberately.
Rust's no-GC, zero-cost-abstraction model fits a long-lived, connection-heavy WebSocket hub better than a garbage-collected runtime, and echo already proved the pattern works at this scale (DashMap-based hub, ticket-based WS auth, Argon2id, JWT access/refresh).
SQLx's compile-time-checked queries catch a real class of bug before it ships: echo's own production incident (`jsonb_array_length` decoding as `i32` vs `i64`, silently eating strokes) was a query-shape bug that stronger compile-time checking narrows the space for.
The owner also has a mature Rust toolchain (rustfmt, clippy budgets, cargo-deny, cargo-audit, CI shape) that transfers directly, lowering maintenance risk more than switching language would save in dev time, and dev time is not the priority here.

I evaluated and rejected Go, Elixir/Phoenix, and Node/TypeScript for the main server.
Go is excellent for the relay but weaker here: its GC introduces latency jitter that is irrelevant for a stateless forwarder but a real ding on a stateful real-time hub, and its weaker type system gives up the compile-time safety SQLx buys in Rust.
Elixir/Phoenix and BEAM are a strong fit for massive WS concurrency, but this is a new runtime paradigm with no convention in either reference codebase, a smaller contributor pool, and a heavier idle VM footprint than Rust; reject as unjustified complexity here.
Node/TypeScript was rejected on weaker memory/CPU efficiency and weaker type safety without heavy added discipline.
Risk of the Rust choice: slower iteration and steeper onboarding than Go; accepted, since the ground rules deprioritize dev cost in favor of quality and maintainability, and the same tradeoff already worked in echo.

**Push relay: Go, extended directly from check-in-relay.**
The brief asks the relay to "function similarly to check-in-relay," a direct reuse signal, not just an inspiration credit.
The relay's job (dumb, stateless, opaque-token forwarding, single static binary, SQLite key store, distroless image) is precisely what check-in-relay already is.
Reusing it, extended with an `internal/apns` package alongside `internal/fcm`, a `platform` field for routing, and a silent/wake-up message type, is cheaper and lower-risk than a rewrite, and fits "lightweight, scalable, inexpensive to operate" better than Rust would add value for here.
Two languages is a real cost, but it is the right tool for two different problems: forcing one language across both would bloat the relay or weaken the main server's real-time hub.

## 2. Module boundaries

Following echo's proven layout, tightened around known gaps:

- `auth/` - Argon2id, JWT access (15 min) and refresh (7 day) issuance, ticket-based WS auth (`POST /api/auth/ws-ticket`, 30s single-use, never a token in the WS URL).
Refresh tokens are bound to `device_id` from day one, closing echo's documented "logout all others only kicks live sessions" gap instead of carrying it forward as debt.
- `ws/` - `hub.rs` (connection registry keyed by user and device, true multi-device fan-out), `handler.rs` (upgrade, ticket verification, dispatch), `events/` (one module per kind: messages, presence, typing, canvas, voice-signaling, moderation), `seq.rs` (server-assigned monotonic sequence numbers per conversation/canvas, applied day one, not bolted on later as echo's unshipped fix was).
- `routes/` - thin REST handlers per resource, delegating to domain/db layers; no business logic in handler bodies.
- `db/` - one module per aggregate, SQLx compile-checked queries, versioned migrations.
- `push/` - relay client behind a `PushSender` trait, swappable or disableable per self-hoster.
- `moderation/` - report intake, audit log, abuse-signal heuristics, kept separate from `ws/` so policy changes stay localized.
- `admin/` - admin-only REST surface, gated by role/permission checks distinct from plain authentication.
- `config/`, `observability/` - as described below.

## 3. API style

REST for anything request/response-shaped (auth, users, servers, channels, invites, admin, moderation, media, voice token minting), WebSocket for anything push/broadcast-shaped (messages, typing, presence, canvas events).
This is the same split echo validated in production, keeping the wire format as plain JSON over WS rather than reviving echo's abandoned early protobuf plan.
GraphQL is rejected as a mismatch for WS-native push events and unnecessary schema complexity here.
gRPC is rejected for weak browser/Flutter-web ergonomics versus plain JSON.
Ship an OpenAPI spec generated from route definitions (via `utoipa`) so the REST surface is browsable and toolable, serving the brief's "readable APIs" goal.

## 4. Config, admin, moderation, observability, extensibility

Config is env-var-first and validated eagerly at startup with fail-fast errors on missing secrets, matching echo's `DATABASE_URL`/`JWT_SECRET` pattern, plus an optional layered TOML file for self-hosters who prefer file-based config (secrets stay env-only).

Admin APIs cover user management, invite management (create/revoke/list with usage caps and TTL, using the same `SELECT ... FOR UPDATE`-in-transaction pattern echo eventually used for canvas caps, applied here from day one to avoid an invite-overuse race), role/permission assignment, diagnostics, and an append-only audit log.
Moderation APIs are deliberately metadata- and report-driven, not content-scanning: if messages are end-to-end encrypted, the server cannot inspect content, so reports carry a reporter-supplied plaintext excerpt, and automated signals stay limited to behavioral patterns (report rate, join rate).
This is a real tension the brief does not resolve: "excellent moderation tools" and "lightweight encryption" pull opposite ways depending on how strong the encryption is meant to be, flagged as an open question below.

Observability is `tracing` plus a Prometheus `/metrics` endpoint (WS connection count, per-event throughput, DB pool stats, request latency histograms), with `/healthz` (liveness) split from `/readyz` (DB reachable, migrations applied), since `/healthz`-only is not enough for an orchestrator to safely gate traffic.
No external metrics stack is bundled by default; a self-hoster wanting Grafana gets a documented optional compose overlay, keeping the base footprint minimal.

Extensibility follows echo's `canvas_validation.rs` pattern: explicit allowlist dispatch tables for event kinds and routes, so adding a type is additive, plus echo's proven `off | log_only | enforce` rollout flag for new server-side validation.
Outbound webhooks for bots are a deliberate v1 deferral, landing after the seq-ordering model is stable, since bots want the same ordered event stream.

## 5. Deployment weight and idle resource targets

Target: `rustls` instead of OpenSSL, so the server ships on a distroless base without a C TLS dependency, aiming for a compressed image under 40 MB (heavier than a Go/distroless relay image, still light for a self-hoster).
Postgres stays external rather than embedded SQLite: write concurrency, join complexity, and the canvas's future per-object table need Postgres's concurrency model, a deliberate divergence from the relay's SQLite choice, not an oversight.

For a small self-hosted instance (roughly under 20 users, mostly idle):

- Server process idle RSS: under 30 MB.
- Postgres idle: under 60 to 80 MB with a small-instance-tuned `postgresql.conf` shipped in the example compose, not defaults.
- Idle CPU: effectively 0%, event-driven, background cleanup ticks no tighter than 30 to 60s.
- Combined idle memory budget: under 150 MB for server plus Postgres, as compose `mem_limit` values.
- Disk: single-digit MB beyond the Postgres data volume, with log rotation documented so idle disk use does not grow unbounded.

## 6. Testing strategy

Unit tests for pure logic (validators, permission checks, seq assignment) colocated per module, matching echo's `canvas_validation.rs` precedent.
Integration tests run against a real ephemeral Postgres, not a mocked DB layer: echo's worst production bug (the JSONB `i32`/`i64` decode issue) would not have been caught by a mocked-DB unit test.
A first-class WS test harness opens real connections and asserts on event ordering and per-device fan-out, covering the device-vs-user-id bug class echo hit (VL-19).
Once seq-based ordering ships, add property-based tests (`proptest`) generating random concurrent event orderings and asserting convergent final state, directly testing echo's single most important lesson.
CI reuses echo's shape almost unchanged: `cargo fmt --check`, `clippy -D warnings`, `cargo test --workspace`, `cargo audit`, `cargo-deny`, secret scanning, plus a periodic (not per-PR) load/soak job benchmarking WS fan-out and canvas throughput, mirroring echo's `perf-baseline.md` precedent.

## Open questions

- How strong must "lightweight encryption" be: transport-only (TLS), or full E2E like echo's Signal Protocol.
This decision determines whether the server ever sees plaintext, and therefore whether real content moderation is possible at all.
- Does invite-only self-hosted account creation need an in-app account-deletion flow and clearer server-discovery disclosure in the app description, given Apple's scrutiny of apps that only function paired with an undisclosed external service.
