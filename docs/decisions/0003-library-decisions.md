# 0003 - Library and tooling decisions from the validation pass

Status: accepted (technical); every recommendation below was independently verified on crates.io, lib.rs, and pub.dev before adoption, and the Linux desktop media question was resolved after correcting an overstatement (see below).
Date: 2026-07-23 (Linux and library-verification corrections added 2026-07-24).
Source: the seven-region library due-diligence pass compiled in [research/stack-validation/SUMMARY.md](../research/stack-validation/SUMMARY.md), independently re-checked against the package registries.

The validation confirmed the architecture and its core libraries as sound.
The choices below are library-level decisions within the fixed architecture, adopted directly.
One item (Linux desktop media) is a scope decision and is carried to the owner.

## Adopted changes

- Rust date and time: use `jiff`, not `chrono`. It bundles the IANA timezone database and DST-aware arithmetic. Verified: jiff is by Andrew Gallant (author of ripgrep and the regex crate), around 17 million downloads per month, used by over 4,000 crates, so it is widely adopted, not new or unproven; the only caveat is it is still pre-1.0 (0.2.x, with a year of bugfix support planned after 1.0), and chrono remains a safe fallback if a 1.0 dependency is required.
- Flutter golden tests: use `alchemist`, not `golden_toolkit`. Verified: golden_toolkit is explicitly marked discontinued on pub.dev and unmaintained for about three years, while alchemist is published by Betterment and Very Good Ventures (the main Flutter consultancy) and updated within the last few months, so this is a safe swap to a maintained successor.
- Token hashing: hash session and refresh tokens with BLAKE3, not SHA-256. Roughly 10x faster with no known weakness; revisit only if FIPS compliance is ever required.
- Server config: start with flat environment-variable config via `envy`; add `figment` only if multi-source layered config becomes necessary, to keep the self-host operational surface minimal.

## Adopted additions

- `Litestream` as a Docker Compose sidecar that continuously streams the SQLite WAL to S3-compatible storage. This is the disaster-recovery path a single-file self-hosted database otherwise lacks, and was independently flagged as a must-have. This is the concrete implementation of the backup requirement.
- Push-payload encryption via libsodium sealed boxes (X25519). The mobile and client sides use real, audited libsodium: a libsodium Swift package inside the iOS Notification Service Extension, Lazysodium on Android, and the `sodium` FFI package in Dart. For the Rust server the validation suggested `dryoc`, but independent checking flags that dryoc is a pure-Rust reimplementation that has NOT had a third-party security audit, so for this security-critical path the safer default is audited libsodium bindings on the server as well, so every side runs the same vetted C implementation and sealed-box interop is guaranteed; dryoc's benefit (pure Rust, no C dependency, easier static musl builds) is weighed against the audit gap when the per-device key model and payload contract are specified before any client or relay code. This is the one validation recommendation deliberately not adopted as-is.
- Spatial indexing for the Voice Canvas so the painter never evaluates thousands of off-screen objects per frame. The `r_tree` Dart package (Workiva, a verified publisher, maintained and cross-platform) is a safe option, but it is a niche utility (about 9k weekly downloads), so a hand-rolled uniform spatial grid, which the strategy already names as the culling approach, is an equally valid dependency-free alternative; decide at implementation.
- Flutter runtime packages that the plan depends on but had not named: `connectivity_plus`, `background_fetch`, `flutter_local_notifications`, and `permission_handler`.
- `tower-http` `TraceLayer` for structured HTTP request tracing, using infrastructure already in the stack.
- CI gates: `cargo-audit` and `cargo-deny` (CVE and license blocking), `oasdiff` (enforces the additive-only OpenAPI rule), and `cosign` plus `slsa-github-generator` (keyless signing and SLSA provenance).

## Confirmed as-is (no change)

Axum, Tokio, Tower, tracing, and sqlx as the server core.
SQLite in WAL mode with the single-writer-plus-read-pool discipline and FTS5 search.
UUIDv7 scoped to event identity only, with CSPRNG 256-bit session tokens (correctly not UUIDv7).
Riverpod (codegen), Drift, GoRouter, Dio, web_socket_channel, and flutter_secure_storage on the client.
LiveKit plus flutter_webrtc for iOS and Android media.
An Impeller-backed CustomPainter for the Voice Canvas. Note: `flutter_box_transform` (movable and resizable window transforms) is verified as reasonably adopted (about 13k weekly downloads, verified publisher) but last updated roughly 16 months ago and still pre-1.0, so it is acceptable to use but flagged as a maintenance risk, and the resize and drag logic is simple enough to fork or hand-roll if it goes stale.
utoipa, schemars, and typify on Rust with openapi_generator_cli on Dart, gated by oasdiff.
cargo-zigbuild, Chainguard base images, nfpm, and Fedora COPR for packaging.
chi, sideshow/apns2, and firebase-admin-go for the Go relay.
Argon2id and rustls or Caddy as the security baseline.

## Already resolved elsewhere (raised by validation, not open)

- TLS termination and server identity: the strategy already scopes the pinned Ed25519 server identity as trust-on-first-use continuity, explicitly not an active-MITM defense, because Caddy terminates TLS. Kept as-is for v1.
- Voice Canvas conflict tiebreaker: already resolved as server-authoritative last-write-wins by per-scope sequence order, which is the deterministic tiebreaker.
- permessage-deflate: a Phase 1 measurement task; enable only with a bounded decompression size to avoid the known compression DoS, decided after measuring real message sizes.
- Per-device push key distribution and device revocation: a design task scheduled in the push-notifications phase before multi-device ships.

## Linux desktop media: corrected finding

The validation pass overstated this, and independent checking corrected it.
LiveKit officially lists Linux among its supported Flutter platforms, and voice (audio) and camera video work on Linux desktop, so the Voice Canvas (which needs voice and camera bubbles, not screen capture) is available on Linux desktop at 1.0.
The one real gap is screen sharing on Wayland: flutter_webrtc has an open bug (flutter-webrtc issue 1542, open since 2024) where its PipeWire and xdg-desktop-portal capture path does not wait for the portal's screen-picker response and crashes, and WebRTC's older X11 capturer does not work under Wayland; Fedora GNOME defaults to Wayland, so this affects the primary desktop target's screen-share path only.
Decision: no LiveKit C++ FFI rewrite and no deferral of Linux voice; Linux desktop ships voice, video, and the Voice Canvas at 1.0.
The narrow Wayland screen-capture gap is validated and closed in the Phase 4 Fedora RTC spike the roadmap already schedules, with fallbacks in priority order: confirm whether a current flutter_webrtc release already handles the portal path, contribute the portal wait-handling fix upstream (small and well-scoped), or fall back to an X11 session for screen capture until the Wayland path lands.
