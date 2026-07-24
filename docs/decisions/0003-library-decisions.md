# 0003 - Library and tooling decisions from the validation pass

Status: accepted (technical), with one owner question pending.
Date: 2026-07-23.
Source: the seven-region library due-diligence pass compiled in [research/stack-validation/SUMMARY.md](../research/stack-validation/SUMMARY.md).

The validation confirmed the architecture and its core libraries as sound.
The choices below are library-level decisions within the fixed architecture, adopted directly.
One item (Linux desktop media) is a scope decision and is carried to the owner.

## Adopted changes

- Rust date and time: use `jiff`, not `chrono`. It bundles the IANA timezone database and DST-aware arithmetic, and chrono is now legacy for new projects.
- Flutter golden tests: use `alchemist`, not `golden_toolkit`. golden_toolkit is discontinued; alchemist is its maintained successor.
- Token hashing: hash session and refresh tokens with BLAKE3, not SHA-256. Roughly 10x faster with no known weakness; revisit only if FIPS compliance is ever required.
- Server config: start with flat environment-variable config via `envy`; add `figment` only if multi-source layered config becomes necessary, to keep the self-host operational surface minimal.

## Adopted additions

- `Litestream` as a Docker Compose sidecar that continuously streams the SQLite WAL to S3-compatible storage. This is the disaster-recovery path a single-file self-hosted database otherwise lacks, and was independently flagged as a must-have. This is the concrete implementation of the backup requirement.
- Push-payload encryption via libsodium sealed boxes (X25519 crypto_box), with a concrete cross-platform library set: `dryoc` on the Rust server, a libsodium Swift package inside the iOS Notification Service Extension, Lazysodium or Bouncy Castle on Android, and the `sodium` package in Dart. This realizes the content-free, on-device-decrypted push design; the per-device key model and payload contract must be specified before client and relay coding begins.
- `r_tree` (Dart) for Voice Canvas spatial indexing, so culling and hit-testing stay near O(log N) and the painter never evaluates thousands of off-screen objects per frame. Add early.
- Flutter runtime packages that the plan depends on but had not named: `connectivity_plus`, `background_fetch`, `flutter_local_notifications`, and `permission_handler`.
- `tower-http` `TraceLayer` for structured HTTP request tracing, using infrastructure already in the stack.
- CI gates: `cargo-audit` and `cargo-deny` (CVE and license blocking), `oasdiff` (enforces the additive-only OpenAPI rule), and `cosign` plus `slsa-github-generator` (keyless signing and SLSA provenance).

## Confirmed as-is (no change)

Axum, Tokio, Tower, tracing, and sqlx as the server core.
SQLite in WAL mode with the single-writer-plus-read-pool discipline and FTS5 search.
UUIDv7 scoped to event identity only, with CSPRNG 256-bit session tokens (correctly not UUIDv7).
Riverpod (codegen), Drift, GoRouter, Dio, web_socket_channel, and flutter_secure_storage on the client.
LiveKit plus flutter_webrtc for iOS and Android media.
An Impeller-backed CustomPainter plus `flutter_box_transform` for the Voice Canvas.
utoipa, schemars, and typify on Rust with openapi_generator_cli on Dart, gated by oasdiff.
cargo-zigbuild, Chainguard base images, nfpm, and Fedora COPR for packaging.
chi, sideshow/apns2, and firebase-admin-go for the Go relay.
Argon2id and rustls or Caddy as the security baseline.

## Already resolved elsewhere (raised by validation, not open)

- TLS termination and server identity: the strategy already scopes the pinned Ed25519 server identity as trust-on-first-use continuity, explicitly not an active-MITM defense, because Caddy terminates TLS. Kept as-is for v1.
- Voice Canvas conflict tiebreaker: already resolved as server-authoritative last-write-wins by per-scope sequence order, which is the deterministic tiebreaker.
- permessage-deflate: a Phase 1 measurement task; enable only with a bounded decompression size to avoid the known compression DoS, decided after measuring real message sizes.
- Per-device push key distribution and device revocation: a design task scheduled in the push-notifications phase before multi-device ships.

## Pending owner decision

- Linux desktop voice, video, and screen share for 1.0. Neither the LiveKit Flutter SDK nor flutter_webrtc has production-ready Linux desktop media today, and flutter_webrtc's PipeWire and Wayland screen capture is broken, which conflicts with the brief naming Fedora a primary desktop platform and with the Voice Canvas living inside voice calls. See the owner decision recorded in a later addendum once made.
