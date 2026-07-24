# slim-m Delivery Roadmap

This is the phased delivery plan for slim-m.
It implements the decisions recorded in [STRATEGY.md](STRATEGY.md) and is readable standalone by a contributor who has never seen the research.
Phases are ordered so that no phase depends on work scheduled in a later phase.
Early phases prioritize Linux (Fedora, GNOME Wayland) and iOS as the primary test targets, per the brief.
The Voice Canvas, the signature feature, gets a dedicated de-risking spike phase before its full build.

Sizing is relative effort only (S, M, L, XL), never a calendar estimate.

Two identity terms recur throughout.
"UUIDv7" means the client-generatable, globally unique event identity used for optimistic local echo and retry idempotency.
"Per-scope sequence" means the server-assigned, strictly monotonic 64-bit number that is the authoritative total order and sync cursor within one ordered stream (a channel's messages, a DM conversation, or a channel's canvas ops), where each stream has its own independent counter.

Dependency legend: a phase lists the earlier phases whose output it consumes.
Nothing points forward.

## Phase 0 - Foundations

Size: M.

Objective: stand up both repositories, the build and release machinery, the quality gates, and the performance measurement scaffolding, so that every later phase inherits a green, gated, measurable baseline rather than retrofitting one.

Deliverables:

- Core monorepo (Rust server, Flutter client, and the shared OpenAPI plus JSON Schema in a `schema/` directory) and a separate relay repo adapted from check-in-relay with an Apache-2.0 LICENSE added; the server is AGPL-3.0, the client and shared schema and the relay are Apache-2.0, with per-package SPDX headers, a REUSE-style license map, and a CI license-allowlist check from day one.
- Dart native pub workspace (no third-party monorepo manager) with the minimal-first package skeleton (`api`, `design_system`, `data`, `platform`, `rtc`, `app`, and a reserved `voice_canvas` boundary), path-only dependencies, a soft 300-line review budget backed by an advisory CI check that excludes generated code, and complexity lints (clippy on Rust, dart analyze plus custom lints on Dart).
- Path-gated CI: a schema codegen job that regenerates Rust and Dart types from `schema/` and fails on any diff, per-language format, lint, and test jobs, and a client-only change that does not trigger a server build; SHA-pinned actions; reviewer-gated GitHub Environments on every publish-capable job.
- release-please in manifest mode with independently versioned server and client components (concrete component-to-path mapping specified, plus a CI check that a `schema/` change bumps both), independent versioning for the relay in its own repo, the repository's squash-merge default commit message set to the PR title, and conventional-commit enforcement on the PR title; the wire envelope protocol version is surfaced in each changelog entry.
- Production Dockerfile (two-stage musl plus rustls with statically linked SQLite on distroless nonroot, a `--healthcheck` subcommand baked in, and the SQLite data directory pre-created and chowned to the nonroot UID) and multi-arch (amd64, arm64) publishing with `FROM --platform=$BUILDPLATFORM` and `ARG TARGETARCH` on both server and relay Dockerfiles so buildx does not fall back to QEMU; cosign keyless signing, SLSA provenance, native Buildx SBOM, GPG signature, and SHA256SUMS wired.
- A CI image-and-artifact size measurement with a regression gate, since binary and image size is an explicit brief requirement.
- Design-token pipeline (primitive and semantic layers compiled to Dart, wired through one AppTokens ThemeExtension) with a CI drift check, an automated WCAG 2.1 AA contrast check on the token file, a Lucide `AppIcons` wrapper, and a CI grep that fails on emoji literals in UI source.
- Golden-test infrastructure with a pinned CI runner image for the light, dark, and true-black by two-viewport by 100 percent and 200 percent font-scale matrix.
- Performance scaffolding: criterion benchmarks, a Rust WebSocket load-test harness, and Flutter FrameTiming and start-time harnesses, all writing one versioned JSON baseline per release; the hot-path list references UUIDv7 identity assignment and per-scope sequence assignment, not any single global ID scheme.

Risks: arm64 GitHub runners are new to this team with zero prior operational history; release-please manifest mode needs correct component and path configuration or it produces phantom releases; the WCAG contrast gate will immediately flag the provisional palette values (border and light accent), which is expected and handled by treating the gate as authoritative.

Dependencies: none.

Exit criteria: CI is green on the empty skeleton; a tagged 0.0.x release automatically produces signed multi-arch server and relay images, a Linux Flatpak and rpm, and an internal TestFlight build; the JSON performance baseline exists; the size-regression gate and the token contrast gate run, and the contrast gate's current failures are triaged into the design track.

## Phase 1 - Server and Protocol Core

Size: L.

Objective: build the Rust server, the embedded SQLite schema, and the JSON-over-WebSocket plus REST protocol with correct ordering, authentication, and revocation, since every client and relay behavior depends on these being right first.

Deliverables:

- SQLite (WAL) schema via sqlx with compile-time-checked queries, a single serialized writer path plus a read-only pool, and all persistence behind a repository trait: full RBAC (roles with a 63-bit permission bitmask, member_roles, one polymorphic channel_overwrites table), users with no email and a deletion tombstone path, devices, refresh_tokens with a family_id and rotation, messages, reactions (resynced with their parent message, not independently sequenced), attachments (sha256 primary key, key_version, is_encrypted, blobs on disk), canvas_objects (x/y/w/h with an R-Tree kept in sync by triggers, never WITHOUT ROWID, is_encrypted), canvas_ops, a channel_seq_counters table keyed by (channel_id, stream) so messages and canvas ops are separate sequence spaces, password_reset_codes, a canvas_audit_log, and invites; forward-only sqlx migrations applied at startup.
- UUIDv7 identity plus a per-scope monotonic 64-bit sequence assigned in the same transaction as the insert, modeled as distinct types, with keyset pagination on (channel_id, seq) and FTS5 external-content search over plaintext messages kept in sync by insert, update, and delete triggers.
- Opaque server-side session tokens (short access, rotating device-bound refresh with reuse detection, SHA-256 hashed), ticket-based WS auth minted from the session token over REST (with its own rate-limit class), and Argon2id at 19 MiB bounded by a concurrency semaphore.
- REST resource endpoints and durable write verbs (send, edit, react, canvas commit) keyed idempotently by UUIDv7; the single typed JSON-over-WS envelope (discriminated type, protocol version, per-scope seq) for server-to-client fan-out plus ephemeral client-to-server signals; the bundled per-scope catch-up sync (capped per scope and in aggregate with a continuation flag and a snapshot-pointer fallback); read state via a monotonic last-read seq with unread derived from an indexed range count; protocol-version and capability negotiation on connect.
- The deny-by-default permission evaluator (@everyone base, union of role bits, channel role overwrites with deny winning, member overwrite absolute, ADMINISTRATOR bypass), authorizing every action server-side including each canvas mutation, with the wire format carrying flags as a byte-array or string bitset.
- Account-deletion protocol verb in the reference server (purge the account's own personal data, tombstone the user, transfer group ownership before completing, revoke devices and refresh tokens).
- Traffic-class-aware backpressure (byte-bounded outbound channel measured pre-compression, hard close on durable overflow with stateless resync, ephemeral frames coalesced latest-per-actor), in-process rate limiting with idle-bucket sweeping and per-device sub-buckets under a shared ceiling, and jittered reconnect handling with one grouped catch-up query per user to absorb correlated reconnect storms.
- Committed .sqlx offline cache verified with `cargo sqlx prepare --check`; integration tests against a real SQLite file; a WS test harness asserting per-scope ordering and per-device fan-out.

Risks: the RBAC evaluator's override precedence is escalation-prone if untested; a bad forward-only migration ships unless the full suite runs against a real SQLite file in CI; idle RSS against the real musl binary may reveal allocator fragmentation, handled by an explicit allocator choice.

Dependencies: Phase 0.

Exit criteria: a two-client integration test passes per-scope ordering, per-device fan-out, and instant token and device revocation; the permission evaluator passes exhaustive precedence tests with deny winning across roles; account deletion (including group ownership transfer) works end-to-end; measured server idle RSS is inside the under-30MB budget.

## Phase 2 - Client Shell and Text Messaging

Size: L.

Objective: deliver a running Flutter client on Fedora and iOS that does full text messaging end-to-end against the Phase 1 server, establishing the app shell, local store, design system, and the account, settings, and report screens the stores require.

Deliverables:

- App shell with GoRouter shell routes and hand-written typed route constants, the width-driven adaptive layout (compact, medium, expanded, never Platform.isX), and Riverpod-codegen state and DI with no second container.
- Drift local store as the single source of truth, keyed by UUIDv7 with an indexed sequence column as the resume cursor, and idempotent upsert-by-UUIDv7 on every write path (WS push and REST catch-up), applied strictly by (scope, sequence).
- Design-system tokens wired through AppTokens with Lucide behind AppIcons and the emoji-literal CI grep; the shared context-menu component (UIContextMenuInteraction on iOS, cursor-positioned on Linux); remappable in-app keyboard shortcuts and an in-app-focused quick switcher; haptics only on deliberate transitions.
- Text messaging end-to-end: send and edit as idempotent REST calls with optimistic local echo, receive and react over the WS fan-out, history with keyset pagination, unread counts, own-device read state, and stateless reconnect-and-resync via per-scope cursors.
- Onboarding with three entry points (join official, redeem invite, connect to self-hosted), an explicit fingerprint-confirmation step for manual server addresses, and a terms-of-use acceptance step at invite redemption.
- Settings and account information architecture: account deletion (wired to the Phase 1 verb), device list, and notification preferences; plus baseline report and block affordances with server-side report intake and user blocking.
- Accessibility baseline: semantics labels, 48x48 tap targets, and the light, dark, and true-black golden matrix passing at 100 percent and 200 percent font scale.
- An explicit early permessage-deflate interop test between the Dart and Rust ends, and a key-storage interface shaped so a future move to hardware-backed non-extractable keys needs no interface change.

Risks: the fixed multi-pane layout must reflow cleanly at 200 percent font scale without clipping; Impeller maturity differs on Linux versus iOS and is verified per platform; golden tests are font-rendering sensitive and are only regenerated on the pinned CI image.

Dependencies: Phase 0, Phase 1.

Exit criteria: full text chat works end-to-end on Fedora GNOME Wayland and iOS against a self-hosted server; account deletion, report, and block work from the client; the golden matrix is green; client cold-start and idle-memory budgets are met on both targets.

## Phase 3 - Push Relay and Notifications

Size: M.

Objective: make backgrounded and offline mobile clients reliably wake and fetch, with the relay carrying only encrypted, content-free payloads, since voice and canvas features later depend on reliable call and message wake-ups.

Deliverables:

- Relay extended with a direct APNs HTTP/2 (.p8 token) path alongside FCM, one key authorizing both via a per-message platform field, a separate APNs voip topic, and a unified deliverability result mapping, with its own SECURITY.md, CODEOWNERS, and MAINTAINERS.md.
- Per-device push-token binding to the registering key, rejecting cross-key sends, to close the standing-harassment vector without a relay devices table.
- A bounded worker-pool send path with a hard per-request deadline returning partial results (or accept-and-poll for large batches), a global registration ceiling, per-device and tighter call-push caps, idle-bucket sweeping on every keyed limiter, and documented single-instance rate-limiting.
- Server-side PushSender with a disable path for NAT-unreachable or LAN-only servers, and reachability surfaced in onboarding as a hard push precondition.
- Per-device push-key encryption (domain-separated sealed-box or HPKE, not the raw identity key); iOS Notification Service Extension that decrypts and selects notification behavior on-device; Android data-only FCM with versioned Notification Channels.
- Push triggering gated on a client-reported foreground and background lifecycle signal, not raw WebSocket presence, so the iOS suspend window is covered, with a short debounce so a burst collapses into one wake.
- A cross-repo push-envelope contract test exercising a real relay against the current server push encoding.

Risks: the encrypt-to-device-key pipeline adds crypto burden to every self-host, accepted for metadata minimization; APNs and FCM report deliverability differently and must prune consistently; provider-side abuse throttling against the shared credentials needs monitoring and an incident plan.

Dependencies: Phase 0, Phase 1, Phase 2.

Exit criteria: a backgrounded iOS device and an Android device each receive a content-free encrypted wake and fetch the message; the relay logs show only ciphertext and a coarse kind; a NAT-unreachable server cleanly uses the disable path; the contract test passes.

## Phase 4 - Voice and Screen Share

Size: L.

Objective: deliver 1:1 and group voice and screen share through a self-hosted LiveKit SFU on Fedora and iOS, including the native call surfaces, opening with the Linux RTC validation spike the media report flags as a real risk.

Deliverables:

- A Linux flutter_webrtc PipeWire and Wayland validation spike on Fedora as the first deliverable (also validating GPU hardware video decode inside the Flatpak sandbox), plus the iOS Broadcast Upload Extension against its roughly 50MB cap, before deep integration.
- LiveKit added to the production docker-compose (server with embedded SQLite on a named volume, no separate database container) with the port-443 contention resolved: Caddy on 443 for the API, LiveKit TURN and TLS on its own documented port with UDP media range and firewall notes, and SNI passthrough or a second IP as advanced options; a periodic CI job boots the compose stack and smoke-tests a healthy multi-service boot.
- The `rtc` package owning the LiveKit Room and client wrapper behind an explicit public API with a Room-injection test seam.
- 1:1 and group voice with Opus audio and VP8 simulcast; screen share with explicit resolution and bitrate ceilings; camera capture capped at 640x480 to 960x540 with DTX.
- LiveKit room capability tokens (short TTL, grants derived from the permission bitfield, room id server-derived, per-role scoping, rejoin nonces), pre-expiry re-mint for mid-call reconnect, and forced eviction via the room-service API on kick or ban.
- A native Swift PushKit and CallKit delegate reporting synchronously on every VoIP push (regression-tested invariant), with kind=call scoped to 1:1 and explicit invites only, never ambient channel joins, plus a per-server call-push mute and reputation limit against abusive well-formed call pushes; Android ConnectionService with a CallStyle notification and the first-call full-screen-intent permission flow plus a tested heads-up fallback; VoIP tokens stored in the server devices table.
- Voice UX: preview and roster before join with mic and camera pre-toggles; voice and canvas-strip as one screen; adaptiveStream and dynacast bound to the (initially empty) viewport.
- An aggregate egress bandwidth budget load-tested for the handful-of-users video room; iOS VP8 decode-side cost measured against the render budget.

Risks: Linux screen share may reveal a flutter_webrtc gap, surfaced early by the spike with a documented fallback; a missed CallKit report is a store-compliance risk, not just UX; group call media is operator-visible by design and disclosed.

Dependencies: Phase 0, Phase 1 (auth and permissions), Phase 3 (VoIP push path).

Exit criteria: 1:1 and group voice and screen share work on Fedora and iOS; a kick force-evicts the participant immediately; the CallKit synchronous-report invariant test is green; the egress budget is measured; active-call memory budgets are met.

## Phase 5 - Voice Canvas De-risking Spike

Size: M.

Objective: prove the Voice Canvas's hardest architectural bets on target hardware before committing to the full build, since the canvas is the signature feature and its subsystems are the highest-risk in the product.

Deliverables:

- A throwaway-or-hardened spike validating 60fps rendering with in-memory uniform-grid spatial culling at the soft-cap object counts (roughly 5,000 on iOS, 20,000 on Linux).
- The in-memory spatial index plus off-Riverpod ChangeNotifier hot path proven to feed the paint layer with no Riverpod StreamProvider in the render loop.
- The server-side R-Tree viewport query and a viewport-delta subscription protocol prototyped so panning a large world streams region objects rather than only the join viewport.
- The LiveKit video-texture layer with viewport-based subscribe and unsubscribe plus hysteresis and debounce, proven not to flicker or thrash keyframes near the boundary.
- World-coordinate camera-bubble and screen-share placement validated as ephemeral presence objects sharing one render list and z-order with persisted content, with recenter-on-drift proven far from the world origin.

Risks: the spike may reveal that a target object count or the streaming protocol needs redesign, which is exactly the outcome it exists to surface cheaply before XL investment.

Dependencies: Phase 0, Phase 1 (per-scope ordering and schema shape), Phase 4 (LiveKit and the rtc package).

Exit criteria: the spike demonstrates 60fps at target counts, a working viewport-delta fetch backed by the R-Tree, and flicker-free media culling on Fedora and iOS, or it produces a documented redesign that the full-build phase adopts before any production canvas code is written.

## Phase 6 - Voice Canvas Full Build

Size: XL.

Objective: build the production Infinite Voice Canvas on the validated architecture, with correct convergence, persistence, undo, memory bounds, and rate limits.

Deliverables:

- The per-object canvas_objects model materialized from an append-only canvas_ops log on its own per-channel sequence stream (separate from the message stream) with an is_encrypted column, and compaction at roughly 30 days that exempts rows tied to open moderation reports, with the lighter canvas_audit_log kept longer.
- Strict apply-by-(scope, sequence), eliminating clear-resurrection, image-move races, and late-joiner double-apply; last-write-wins conflict with an advisory-only move hint and no server-side locking.
- The viewport-delta subscription in production, with canvas reconnect discarding local state for a fresh materialized snapshot of the visible region rather than replaying raw ops, and in-flight drag frames as ephemeral relay-only frames whose pointer-up commit is a durable REST write.
- Render layers with narrow RepaintBoundary triggers (background grid, committed strokes, in-flight stroke, images and windows, presence video textures); the presence video layer wired to LiveKit via a track-reference field; the bounded world (roughly plus or minus 5,000,000 logical px) with recentering.
- Freeform drawing, pasted images and GIFs, movable and resizable windows; a bounded LRU decoded-bitmap cache (96MB iOS, 256MB Linux) with mip-tier swap and an 8-GIF animation cap.
- Undo as an inverse op with its own sequence, restricted to the object's author or a moderate-permission member; a surfaced soft object cap plus a high hard ceiling with a clear error, never a silent drop.
- Split canvas rate limits (a strict persisted-op cap and a separate byte-rate cap for ephemeral relay-only preview frames); collapse-to-strip that actually unmounts and suspends the spatial index and paint layers for voice-only participants.
- A text-based canvas activity-log accessibility fallback.

Risks: op-log growth and cache eviction pop-in are managed by compaction and mip-tiers; the day-one object-count and cache tuning is validated against telemetry and adjusted rather than assumed.

Dependencies: Phase 0, Phase 1, Phase 4, Phase 5.

Exit criteria: a two-client canvas session converges under concurrent edits (property test on convergence) with no clear-resurrection; a client panning a large world reaches all objects; 60fps and the memory-cache budgets hold at the soft-cap object counts on Fedora and iOS.

## Phase 7 - Administration, Moderation, and Metrics

Size: M.

Objective: deliver the administration and moderation tooling the brief mandates and the stores require for approval, plus performance metrics tracked over time.

Deliverables:

- Admin console information architecture and API: user management, invite management, a roles and permissions editor, diagnostics, logging, and health monitoring.
- A moderation queue building on the Phase 2 report and block intake, driven by manual user reports (no automated content or media scanning, per owner decision), with published contact info and no fixed official-instance response SLA (illegal-content and safety reports escalated on discovery).
- A narrow CSAM and legal-reporting design and implementation pass for the official US instance's own actual-knowledge obligations (act on reports, report known material to the relevant authority on discovery, no proactive scanning), plus the client capability handshake that verifies a server exposes report and block before connecting and warns if absent.
- Performance metrics: an auth-gated (or network-isolated) /metrics Prometheus endpoint plus a built-in SQLite time-series store (raw 24h, 5-minute averages 30d, daily averages 1y) rendered as admin graphs, with its own measured RAM, CPU, and disk budget.

Risks: the metrics store taxes the same process the idle budget covers and must be measured against it; single-maintainer governance means the official instance publishes no response SLA and escalates only illegal-content and safety reports on discovery, stated honestly.

Dependencies: Phase 0, Phase 1, Phase 2.

Exit criteria: an admin can manage users, invites, and roles, action reports from the queue, and view performance graphs over time; the metrics store stays within its budget; the content and legal-reporting policy is documented and the capability handshake is enforced client-side.

## Phase 8 - Audio Design and Interaction Polish

Size: M.

Objective: deliver the synthesized notification sound family and the final interaction polish, so the product feels finished across all three platforms.

Deliverables:

- The numpy additive-synthesis pipeline with a shared synth.py, seven sounds sharing one bell-like timbre distinguished by contour, count, and duration, pyloudnorm normalization with a whole-clip K-weighted RMS fallback for sub-400ms clips, and a CI job that regenerates WAVs from CI only and diffs.
- Per-platform playback: iOS .ambient foreground player plus NSE on-device sound selection with call-session precedence rules; Android versioned Notification Channels; Linux foreground PipeWire playback; a separate CallKit ringtone bundled file scoped by platform and call direction; a CI bundle-check so a missing file never silently falls back.
- Motion, haptic, hover, and transition polish per the design language (platform-idiomatic transitions, reduce-motion respected, debounced zoom-limit haptic), and a pixel-perfection pass across the primary flows.

Risks: cross-platform loudness perception can be misread as a bug and is documented as relative-not-absolute normalization; three iOS audio paths add surface, mitigated by the CI bundle-check.

Dependencies: Phase 0, Phase 2 (client shell), Phase 3 (NSE), Phase 4 (CallKit and call audio session).

Exit criteria: seven distinguishable, consistently normalized sounds play correctly on Fedora, iOS, and Android; in-app chimes never glitch a live call; reduce-motion collapses non-essential motion; the polish pass has no known visible defects in the primary flows.

## Phase 9 - Release Readiness and Store Submission

Size: M.

Objective: finalize compliance, deployment simplicity, and the 1.0 release across all supported channels.

Deliverables:

- App Store and Play compliance closeout: 18+ rating plus Play IARC and target-audience declaration, always-visible account deletion, report, and block, terms-of-use gate, VoIP entitlement with the CallKit invariant test, screen-share permissions, privacy nutrition labels with the self-hosted-server publisher-visibility disclaimer, App Review notes, and a standing demo self-hosted deployment.
- Finalized production docker-compose (server with embedded SQLite, Caddy, LiveKit) with a well-documented one-command deployment, a backup story (VACUUM INTO hot copy plus attachment tarball with the server encryption key stored and backed up separately, and restore-and-checksum drills), and a documented reverse-proxy fallback.
- Linux artifacts (Flatpak primary, rpm alongside) and the iOS TestFlight-to-production path, all signed with cosign, SLSA provenance, GPG, and SHA256SUMS, and the official-instance explicit deploy-on-release-merge step.
- Flathub and OARS noted as tracked future scope; the final project name chosen to replace the "slim-m" working name (owner decision 9, the one deliberately deferred item).

Risks: the dual-path (official plus self-hosted) account model is a novel App Review shape, mitigated by explicit reviewer notes and the demo server; a real-device-only iOS regression can lag main until the periodic job catches it, an accepted gap.

Dependencies: Phases 0 through 8.

Exit criteria: the store-readiness checklist passes; a one-command self-host works on a fresh Fedora host and an arm64 board; a signed 1.0 is tagged and produces all platform artifacts automatically.

## Phase Dependency Summary

- Phase 0: no dependencies.
- Phase 1: Phase 0.
- Phase 2: Phases 0, 1.
- Phase 3: Phases 0, 1, 2.
- Phase 4: Phases 0, 1, 3.
- Phase 5: Phases 0, 1, 4.
- Phase 6: Phases 0, 1, 4, 5.
- Phase 7: Phases 0, 1, 2.
- Phase 8: Phases 0, 2, 3, 4.
- Phase 9: Phases 0 through 8.

Every dependency points backward; no phase requires work scheduled later.
The design track (validating the palette against the CI contrast gate and the designer review) runs in parallel from Phase 0, since the token pipeline and gate exist from the start and the visual identity is decoupled from widget code by design.
