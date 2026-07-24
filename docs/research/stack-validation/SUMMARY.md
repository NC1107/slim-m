# slim-m Stack Validation: Compiled Verdict

This is the compiled verdict from seven regional due-diligence reports covering the Rust server core, the SQLite data layer, the Flutter client, the media and Voice Canvas stack, the wire-protocol codegen pipeline, DevOps and packaging and the push relay, and security and crypto.
It is written for a decision-maker who needs to know what to build on, what to change, what to add, and what still needs a call.

## Overall Health

The stack is in good shape.
Every region independently confirms that the architecture's big choices, Axum and Tokio on the server, SQLite in WAL mode via sqlx, Riverpod and Drift and GoRouter on the Flutter client, LiveKit and Impeller for media and canvas, utoipa and openapi-generator for schema-first codegen, cargo-zigbuild and Chainguard for release engineering, are correct, actively maintained, and permissively licensed as of July 2026.
No report found a reason to swap the architecture itself.
The changes worth making are narrow and mostly additive: a couple of small library swaps, three items that need to be specified before coding starts (push-payload encryption, session-token generation, and Argon2 concurrency bounding), and one genuine architectural gap, Linux desktop voice and video, that conflicts with the brief's choice of Fedora as a primary desktop testing platform and needs an owner decision.
None of this should slow the team down; it should be resolved in the first one to two weeks of implementation, not discovered mid-build.

## Confirmed Solid

- Axum, Tokio, Tower, tracing, and sqlx form the correct, production-ready foundation for the Rust server core, with no critical blockers.
- SQLite in WAL mode, accessed through sqlx's single-writer-plus-read-pool discipline with compile-time-checked queries, is the right persistence model for a self-hosted single-file database, with concrete monitoring triggers already defined for a future Postgres swap via the repository trait.
- FTS5 is sufficient for full-text search with no additional dependency.
- UUIDv7 is correctly scoped to message and event identity; the token design already correctly uses CSPRNG-generated 256-bit tokens rather than UUIDv7 for sessions, this just needs to stay explicit in implementation.
- Riverpod 3.3+ with codegen, Drift, GoRouter, Dio, web_socket_channel, and flutter_secure_storage remain the right 2026 consensus stack for the Flutter client.
- LiveKit's official Flutter SDK plus flutter_webrtc is confirmed for iOS and Android voice, video, and screen share.
- Impeller-backed CustomPainter, combined with flutter_box_transform for movable and resizable windows, is the right rendering model for the Voice Canvas.
- utoipa, schemars, and typify on the Rust side, paired with openapi_generator_cli on the Dart side and oasdiff as a CI gate, form a sound schema-first pipeline with no material replacement needed.
- cargo-zigbuild, Chainguard base images, cosign and slsa-github-generator for provenance, and nfpm plus Fedora COPR for Linux packaging all fit the brief's lightweight, Docker-first self-hosting goals.
- chi, sideshow/apns2, and firebase-admin-go are the right, lightweight choices for the Go push relay's router and push-delivery clients.
- argon2id for password hashing, rustls and Caddy for TLS, and cargo-deny plus cargo-audit for supply-chain auditing form a sound security baseline.

## Changes to Consider

Most of these are low-churn, targeted swaps rather than rethinks.

1. **Datetime handling.**
   Current: chrono.
   Proposed: jiff.
   Why: jiff bundles the IANA timezone database and DST-aware arithmetic without extra dependencies, and is now considered the better default for new Rust projects; chrono is functional but carries legacy baggage.
   This recommendation appeared independently in both the rust-server-core and security-crypto-push reports.
   Confidence: high.

2. **Flutter golden testing.**
   Current: golden_toolkit.
   Proposed: alchemist.
   Why: golden_toolkit is discontinued and unmaintained; alchemist is its actively maintained, community-accepted successor.
   This is the one change flagged as critical rather than optional.
   Confidence: high.

3. **Linux desktop voice, video, and screen share.**
   Current: livekit_client plus flutter_webrtc used uniformly across platforms.
   Proposed: use the LiveKit C++ SDK via Dart FFI for Linux desktop media, or explicitly defer Linux desktop voice and screen share to a post-1.0 release.
   Why: neither livekit_client nor flutter_webrtc has production-ready Linux desktop support, and flutter_webrtc's PipeWire and Wayland screen capture is actively broken.
   This directly affects the brief's choice of Fedora as a primary desktop testing environment for anything beyond text chat and the canvas itself.
   Confidence: medium, the problem is confirmed, the right fix depends on an owner scoping decision (see Open Questions).

4. **Session and refresh token hashing.**
   Current: SHA-2 (the implied default, not yet specified in the architecture).
   Proposed: BLAKE3.
   Why: roughly ten times faster than SHA-256 on modern CPUs with no known weaknesses and the same permissive licensing; only stay on SHA-2 if FIPS compliance becomes a requirement.
   Confidence: medium, this is a nice-to-have performance and simplicity win, not a correctness issue.

5. **Image caching for web and desktop.**
   Current: cached_network_image (official package).
   Proposed: cached_network_image Community Edition.
   Why: the official package has no persistent caching on web and can bloat memory with many canvas images; the community edition adds IndexedDB-backed persistence.
   Confidence: medium, and only relevant if web or heavy desktop image usage is prioritized; the brief does not list web as a target platform.

6. **Server configuration loading.**
   Current: figment, as referenced in the architecture for layered config.
   Proposed: start with envy for flat environment-variable configuration, and only add figment if multi-source config becomes genuinely necessary.
   Why: keeps operational surface area minimal for self-hosted admins running a single Docker Compose deployment.
   Confidence: low, this is a simplification, not a fix for anything broken.

## Additions to Adopt

These are the specific libraries and tools the research says clearly improve the setup, ordered roughly by how load-bearing they are.

1. **Litestream** for SQLite backup and disaster recovery.
   Runs as a Docker Compose sidecar, continuously streaming the WAL to S3-compatible storage.
   Two independent reports call this a must, not a nice-to-have: for a single-file self-hosted database with no DBA on hand, this is the difference between a recoverable outage and permanent data loss.
   Pair it with a health check surfaced in the admin UI so a silent backup failure does not go unnoticed.

2. **Cross-platform push-payload encryption**: dryoc on the Rust server, the Sodium Swift package on iOS, Bouncy Castle on Android, and the sodium package on Dart and Flutter, all implementing libsodium sealed boxes.
   This is the concrete library set needed to deliver the brief's content-free, on-device-decrypted push design, and it is flagged as a hard blocker: the per-device key model and payload contract must be specified before client and relay coding begins, not discovered mid-build.

3. **connectivity_plus, background_fetch, flutter_local_notifications, and permission_handler** for the Flutter client.
   These are load-bearing for offline-first chat, background wake-ups from the push relay, and camera and microphone permission flows for voice calls and the Voice Canvas.

4. **r_tree** for Voice Canvas spatial indexing.
   Culls and hit-tests canvas objects in roughly O(log N) time so CustomPainter is never forced to evaluate thousands of off-screen drawing commands per frame.
   Flagged as high priority to add early, before performance problems appear at scale.

5. **tower-http's TraceLayer** for HTTP observability on the Rust server.
   Adds structured request and response tracing using infrastructure already in the stack, with no new external dependency.

6. **cargo-audit and cargo-deny** as mandatory CI gates on the Rust side.
   Blocks the build on known CVEs and disallowed licenses; lightweight, fast, and recommended independently by two reports.

7. **oasdiff** as a CI gate on the OpenAPI schema.
   Automatically enforces the additive-only versioning rule the wire protocol depends on, catching breaking changes before they ship rather than after.

8. **cosign plus slsa-github-generator** in the release pipeline.
   Adds keyless artifact signing and SLSA Level 3 build provenance to GHCR images and release binaries, achievable in roughly an afternoon of GitHub Actions setup.

## Open Questions for the Owner

These are genuine decisions the research surfaced that only the project owner can make; the libraries below cannot be finalized until they are answered.

1. **Is Linux desktop voice, video, and screen share in scope for 1.0?**
   The brief names Fedora as a primary desktop testing environment, but neither livekit_client nor flutter_webrtc has production Linux desktop media support today.
   If yes, budget real time (the media report estimates four to six weeks) for a LiveKit C++ SDK FFI integration or an XDG Desktop Portal wrapper.
   If no, Linux desktop can ship with text chat and the Voice Canvas working, with voice and screen share deferred to a 1.1 release.

2. **How should TLS termination and server identity binding work together?**
   Caddy terminating TLS in front of a plaintext-behind-the-proxy Rust app is the simplest self-hosting story, but it means the app cannot bind its Ed25519 identity key to the client-facing TLS session, undermining the claimed MITM resistance.
   The choice is between adding an application-layer identity handshake on top of Caddy, or terminating TLS inside the Rust app and giving up some of Caddy's convenience.

3. **Per-device push key distribution and device management.**
   The research recommends one X25519 keypair per device, generated on-device and never shared, with the server tracking which public key belongs to which device.
   This requires a device-management and revocation flow (list active devices, delete a compromised device and lose its push access) that has not yet been scoped; it needs to be designed before multi-device support ships.

4. **Should WebSocket frames be compressed with permessage-deflate, or left to the reverse proxy?**
   Axum and tungstenite do not enable permessage-deflate automatically, and it carries a known DoS risk (CVE-2026-39804) if the decompressed size is not bounded.
   The simplest path is to let Caddy handle compression at the edge; the alternative is explicit tungstenite configuration with a hard cap on decompression output.
   Recommend measuring real message sizes early and letting data decide.

5. **What is the collaborative canvas conflict-resolution rule?**
   When two users draw on the same region of the Voice Canvas at the same time, the system needs a deterministic tiebreaker, for example comparing UUIDs or timestamps, layered on top of the existing append-only, sequence-numbered operation log.
   This is explicitly flagged as needing sign-off before the 1.0 beta, since it affects both the wire protocol and the client's local replay logic.
