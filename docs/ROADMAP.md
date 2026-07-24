# slim-m Delivery Roadmap

This is the phased delivery plan for slim-m.
It implements the decisions recorded in [STRATEGY.md](STRATEGY.md) and is readable standalone by a contributor who has never seen the research.
Phases are ordered so that no phase depends on work scheduled in a later phase.
Early phases prioritize Linux (Fedora GNOME Wayland) and iOS as the primary test targets, per the brief.
The Voice Canvas, the signature feature, gets a dedicated de-risking spike phase before its full build.

Sizing is relative effort only (S, M, L, XL), never a calendar estimate.
"Snowflake ID" throughout means the single global 64-bit server-assigned identifier that is both identity and total-order key for every persisted event; it has reserved node-id bits so multiple writer processes remain possible later.

Dependency legend: a phase lists the earlier phases whose output it consumes.
Nothing points forward.

## Phase 0 - Foundations

Size: M.

Objective: stand up both repositories, the build and release machinery, the quality gates, and the performance measurement scaffolding, so that every later phase inherits a green, gated, measurable baseline rather than retrofitting one.

Deliverables:

- Core monorepo (server plus client) and a separate relay repo forked from check-in-relay with an AGPL-3.0 LICENSE added; client and shared-protocol code marked Apache-2.0, with a per-crate/per-package license-field CI check.
- Melos workspace with the minimal-first package skeleton (design_system, data, platform, rtc, voice_canvas, app), path-only dependencies, and the 300-line file-budget lint plus a custom_lint rule stub for Result-type boundaries.
- Path-gated CI treated as a new build, not a port; SHA-pinned actions; reviewer-gated GitHub Environments on any publish-capable job.
- release-please in manifest mode with a linked-versions group for client and server, independent versioning for the relay, conventional-commit enforcement via commitlint and lefthook.
- Production Dockerfile (two-stage musl plus rustls on distroless nonroot) and multi-arch (amd64, arm64) publishing with `FROM --platform=$BUILDPLATFORM` and `ARG TARGETARCH` so buildx does not fall back to QEMU; cosign keyless signing, SLSA provenance, CycloneDX SBOM, GPG signature, and SHA256SUMS wired.
- Design-token pipeline (primitive and semantic layers compiled to Dart, wired through one AppTokens ThemeExtension) with a CI drift check and an automated WCAG 2.1 AA contrast check on the token file.
- Golden-test infrastructure with a pinned CI runner image for the light/dark/true-black x two-viewport x 100%/200% font-scale matrix.
- Performance scaffolding: criterion benchmarks, a Rust WebSocket load-test harness, and Flutter FrameTiming and start-time harnesses, all writing one versioned JSON baseline per release; the hot-path list references snowflake ID assignment, not any per-channel counter.

Risks: arm64 GitHub runners are new to this team with zero prior operational history; release-please manifest plus linked-versions needs correct configuration or it produces phantom releases; the WCAG contrast gate will immediately flag the provisional palette values (border and light accent), which is expected and handled by treating the gate as authoritative.

Dependencies: none.

Exit criteria: CI is green on the empty skeleton; a tagged 0.0.x release automatically produces signed multi-arch server and relay images, a Linux AppImage, and an internal TestFlight build; the JSON performance baseline exists; the token contrast gate runs and its current failures are triaged into the design track.

## Phase 1 - Server and Protocol Core

Size: L.

Objective: build the Rust home server, the PostgreSQL schema, and the JSON-over-WebSocket protocol with correct ordering, authentication, and revocation, since every client and relay behavior depends on these being right first.

Deliverables:

- PostgreSQL schema with full RBAC (roles, member_roles, channel_role_overrides, channel_member_overrides), users with a deletion/anonymization path and explicit ON DELETE on every FK, devices, sessions/refresh_tokens (token_hash, device_id, family_id, revoked_at), messages, reactions, attachments (UNIQUE sha256, hash-before-encrypt, is_encrypted), and canvas_ops (is_encrypted); forward-only sqlx migrations with documented concurrent-index and additive-backfill patterns.
- Snowflake ID generator with reserved node-id bits (default 0) and a backward-clock guard, as the sole identity and ordering mechanism.
- Opaque server-side session tokens (short access, rotating device-bound refresh with reuse detection, SHA-256 hashed), ticket-based WS auth minted from the session token, and Argon2id at 19 MiB bounded by a concurrency semaphore sized to the memory budget.
- REST resource endpoints, the single JSON-over-WS envelope, the unified sync cursor (`GET /api/sync?after=<id>&kinds=...`), read-state via GREATEST-monotonic last_read plus a single grouped unread aggregate, and protocol-version-plus-capability negotiation on connect.
- The deny-by-default permission evaluator over the bitfield, authorizing every action server-side, with the wire format carrying flags as a byte-array/string bitset.
- Account-deletion protocol verb in the reference server (purge content, retain tombstones, anonymize user, transfer ownership).
- Committed .sqlx offline cache verified with `cargo sqlx prepare --check`; ephemeral-Postgres integration tests; a WS test harness asserting event ordering and per-device fan-out.

Risks: the RBAC evaluator's override precedence is escalation-prone if untested; a rolling deploy briefly runs two writers, handled by distinct node-ids; idle RSS against the real musl binary may reveal allocator fragmentation, handled by an explicit allocator choice.

Dependencies: Phase 0.

Exit criteria: a two-client integration test passes ordering, per-device fan-out, and instant token/device revocation; the permission evaluator passes exhaustive precedence tests; account deletion works end-to-end against the schema; measured server idle RSS is inside the under-30MB budget.

## Phase 2 - Client Shell and Text Messaging

Size: L.

Objective: deliver a running Flutter client on Fedora and iOS that does full text messaging end-to-end against the Phase 1 server, establishing the app shell, local store, design system, and the account/settings/report screens the stores require.

Deliverables:

- App shell with GoRouter shell routes, the width-driven adaptive layout (compact/medium/expanded, never Platform.isX), and Riverpod-codegen state and DI.
- Drift local store as the single source of truth, with idempotent upsert-by-snowflake-id on every write path (WS push and REST catch-up).
- Design-system tokens wired through AppTokens; the shared context-menu component (UIContextMenuInteraction on iOS, cursor-positioned on Linux); remappable in-app keyboard shortcuts and a quick switcher scoped as in-app-focused; haptics only on deliberate transitions.
- Text messaging end-to-end: send, receive, reactions, history with keyset pagination, unread counts, own-device read state, and reconnect via the sync cursor.
- Onboarding with three entry points (join official, redeem invite, connect to self-hosted), an explicit fingerprint-confirmation step for manual server addresses, and a terms-of-use acceptance step at invite redemption.
- Settings/account information architecture: account deletion (wired to the Phase 1 verb), device list, and notification preferences; plus baseline report and block affordances with server-side report intake and user blocking.
- Accessibility baseline: semantics labels, 48x48 tap targets, and the light/dark/true-black golden matrix passing at 100% and 200% font scale.

Risks: the fixed three-pane layout must reflow cleanly at 200% font scale without clipping; Impeller maturity differs on Linux versus iOS and is verified per platform; golden tests are font-rendering sensitive and are only regenerated on the pinned CI image.

Dependencies: Phase 0, Phase 1.

Exit criteria: full text chat works end-to-end on Fedora GNOME Wayland and iOS against a self-hosted server; account deletion, report, and block work from the client; the golden matrix is green; client cold-start and idle-memory budgets are met on both targets.

## Phase 3 - Push Relay and Notifications

Size: M.

Objective: make backgrounded and offline mobile clients reliably wake and fetch, with the relay carrying only encrypted, content-free payloads, since voice and canvas features later depend on reliable call and message wake-ups.

Deliverables:

- Relay extended with a direct APNs HTTP/2 (.p8 token) path alongside FCM, one key authorizing both via a per-message platform field, a separate APNs voip topic, and a unified deliverability result mapping.
- Per-device push-token binding to the registering key, rejecting cross-key sends, to close the standing-harassment vector without a relay devices table.
- A bounded worker-pool send path with a hard per-request deadline returning partial results (or accept-and-poll for large batches), a global registration ceiling, per-device and tighter call-push caps, and documented single-instance rate-limiting.
- Home-server PushSender with a disable path for NAT-unreachable/LAN-only servers, and reachability surfaced in onboarding as a hard push precondition.
- Per-device push-key encryption (domain-separated sealed-box/HPKE, not the raw identity key); iOS Notification Service Extension that decrypts and selects notification behavior on-device; Android data-only FCM with versioned Notification Channels.
- Push triggering gated on a client-reported foreground/background lifecycle signal, not raw WebSocket presence, so the iOS suspend window is covered.
- A cross-repo push-envelope contract test exercising a real relay against the current server push encoding.

Risks: the encrypt-to-device-key pipeline adds crypto burden to every self-host, accepted for metadata minimization; APNs/FCM report deliverability differently and must prune consistently; provider-side abuse throttling against the shared credentials needs monitoring and an incident plan.

Dependencies: Phase 0, Phase 1, Phase 2.

Exit criteria: a backgrounded iOS device and an Android device each receive a content-free encrypted wake and fetch the message; the relay logs show only ciphertext and a coarse kind; a NAT-unreachable server cleanly uses the disable path; the contract test passes.

## Phase 4 - Voice and Screen Share

Size: L.

Objective: deliver 1:1 and group voice and screen share through a self-hosted LiveKit SFU on Fedora and iOS, including the native call surfaces, opening with the Linux RTC validation spike the media report flags as a real risk.

Deliverables:

- A Linux flutter_webrtc PipeWire/Wayland validation spike on Fedora as the first deliverable, plus the iOS Broadcast Upload Extension against its ~50MB cap, before deep integration.
- LiveKit added to the production docker-compose with the port-443 contention resolved (Caddy on 443 for API; LiveKit TURN/TLS on its own documented port with UDP range and firewall notes; SNI passthrough or second IP as advanced options).
- The rtc package owning the LiveKit Room/client wrapper behind an explicit public API with a Room-injection test seam.
- 1:1 and group voice with Opus audio and VP8 simulcast; screen share with explicit resolution/bitrate ceilings; camera capture capped at 640x480 to 960x540 with DTX.
- LiveKit room capability tokens (short TTL, grants derived from the permission bitfield), pre-expiry re-mint for mid-call reconnect, and forced eviction via the room-service API on kick/ban.
- A native Swift PushKit/CallKit delegate reporting synchronously on every VoIP push (regression-tested invariant), with kind=call scoped to 1:1 and explicit invites only, never ambient channel joins; Android ConnectionService with a CallStyle notification and the first-call full-screen-intent permission flow plus a tested heads-up fallback; VoIP tokens stored in the home server devices table.
- Voice UX: preview/roster before join with mic/camera pre-toggles; voice and canvas-strip as one screen; adaptiveStream/dynacast bound to the (initially empty) viewport.
- An aggregate egress bandwidth budget load-tested for the handful-of-users video room; iOS VP8 decode-side cost measured.

Risks: Linux screen share may reveal a flutter_webrtc gap, surfaced early by the spike with a documented fallback; a missed CallKit report is a store-compliance risk, not just UX; group call media is operator-visible by design and disclosed.

Dependencies: Phase 0, Phase 1 (auth and permissions), Phase 3 (VoIP push path).

Exit criteria: 1:1 and group voice and screen share work on Fedora and iOS; a kick force-evicts the participant immediately; the CallKit synchronous-report invariant test is green; the egress budget is measured; active-call memory budgets are met.

## Phase 5 - Voice Canvas De-risking Spike

Size: M.

Objective: prove the Voice Canvas's hardest architectural bets on target hardware before committing to the full build, since the canvas is the signature feature and echo's history shows its subsystems are the highest-risk.

Deliverables:

- A throwaway-or-hardened spike validating 60fps rendering with spatial-grid culling at the soft-cap object counts (roughly 5,000 on iOS, 20,000 on Linux).
- The in-memory spatial index plus off-Riverpod ChangeNotifier hot-path proven to feed the paint layer with no Riverpod StreamProvider in the render loop.
- The viewport-delta subscription protocol prototyped so panning a large world streams region objects rather than only the join viewport.
- The LiveKit video-texture layer with viewport-based subscribe/unsubscribe plus hysteresis and debounce, proven not to flicker or thrash keyframes near the boundary.
- World-coordinate camera-bubble and screen-share placement validated as ephemeral presence objects sharing one render list and z-order with persisted content.

Risks: the spike may reveal that a target object count or the streaming protocol needs redesign, which is exactly the outcome it exists to surface cheaply before XL investment.

Dependencies: Phase 0, Phase 1 (snowflake ordering and schema shape), Phase 4 (LiveKit and the rtc package).

Exit criteria: the spike demonstrates 60fps at target counts, a working viewport-delta fetch, and flicker-free media culling on Fedora and iOS, or it produces a documented redesign that the full-build phase adopts before any production canvas code is written.

## Phase 6 - Voice Canvas Full Build

Size: XL.

Objective: build the production Infinite Voice Canvas on the validated architecture, with correct convergence, persistence, undo, memory bounds, and rate limits.

Deliverables:

- The per-object canvas_objects model materialized from an append-only, snowflake-ordered canvas_ops log with an is_encrypted column, and compaction at ~30 days that exempts rows tied to open moderation reports.
- Strict apply-by-snowflake-id, eliminating clear-resurrection, image-move races, and late-joiner double-apply; last-write-wins conflict with an advisory-only move hint (no server locking).
- The viewport-delta subscription in production, with canvas reconnect discarding local state for a fresh materialized snapshot of the visible region rather than replaying raw ops.
- Five render layers with narrow RepaintBoundary triggers; the presence video layer wired to LiveKit via a track-reference field; the bounded world (roughly plus or minus 5,000,000 logical px) with recentering.
- Freeform drawing, pasted images and GIFs, movable and resizable windows; a bounded LRU decoded-bitmap cache (96MB iOS, 256MB Linux) with mip-tier swap and an 8-GIF animation cap.
- Undo as an inverse op restricted to the object's author or a moderate-permission member; a surfaced soft object cap plus a high hard ceiling with a clear error, never a silent drop.
- Split canvas rate limits (a strict persisted-op cap and a separate byte-rate cap for ephemeral relay-only preview frames); collapse-to-strip that actually unmounts/suspends the spatial index and paint layers for voice-only participants.
- A text-based canvas activity-log accessibility fallback.

Risks: op-log growth and cache eviction pop-in are managed by compaction and mip-tiers; the day-one object-count and cache tuning is validated against telemetry and adjusted rather than assumed.

Dependencies: Phase 0, Phase 1, Phase 4, Phase 5.

Exit criteria: a two-client canvas session converges under concurrent edits (property test on convergence) with no clear-resurrection; a client panning a large world reaches all objects; 60fps and the memory-cache budgets hold at the soft-cap object counts on Fedora and iOS.

## Phase 7 - Administration, Moderation, and Metrics

Size: M.

Objective: deliver the administration and moderation tooling the brief mandates and the stores require for approval, plus performance metrics tracked over time.

Deliverables:

- Admin console information architecture and API: user management, invite management, a roles/permissions editor, diagnostics, logging, and health monitoring.
- A moderation queue building on the Phase 2 report/block intake, driven by manual user reports (no automated content or media scanning, per owner decision), with published contact info and no fixed official-instance response SLA (illegal-content and safety reports escalated on discovery).
- Performance metrics: an auth-gated (or network-isolated) /metrics Prometheus endpoint plus a built-in Postgres time-series store (raw 24h, 5-minute averages 30d, daily averages 1y) rendered as admin graphs, with its own measured RAM/CPU/disk budget.
- A documented content and legal-reporting policy for the official instance (manual reporting, act on reports, report known CSAM to the relevant authority on discovery, no proactive scanning), and the client capability handshake that verifies a server exposes report/block before connecting.

Risks: the metrics store taxes the same process the idle budget covers and must be measured against it; single-maintainer governance means the official instance publishes no response SLA and escalates only illegal-content and safety reports on discovery, stated honestly.

Dependencies: Phase 0, Phase 1, Phase 2.

Exit criteria: an admin can manage users, invites, and roles, action reports from the queue, and view performance graphs over time; the metrics store stays within its budget; the content and legal-reporting policy is documented and the capability handshake is enforced client-side.

## Phase 8 - Audio Design and Interaction Polish

Size: M.

Objective: deliver the synthesized notification sound family and the final interaction polish, so the product feels finished across all three platforms.

Deliverables:

- The numpy additive-synthesis pipeline with a shared synth.py, seven sounds sharing one bell-like timbre distinguished by contour/count/duration, pyloudnorm normalization with a whole-clip K-weighted RMS fallback for sub-400ms clips, and a CI job that regenerates WAVs from CI only and diffs.
- Per-platform playback: iOS .ambient foreground player plus NSE on-device sound selection with call-session precedence rules; Android versioned Notification Channels; Linux foreground PipeWire playback; a separate CallKit ringtone bundled file scoped by platform and call direction; a CI bundle-check so a missing file never silently falls back.
- Motion, haptic, hover, and transition polish per the design language (platform-idiomatic transitions, reduce-motion respected, debounced zoom-limit haptic), and a pixel-perfection pass across the primary flows.

Risks: cross-platform loudness perception can be misread as a bug and is documented as relative-not-absolute normalization; three iOS audio paths add surface, mitigated by the CI bundle-check.

Dependencies: Phase 0, Phase 2 (client shell), Phase 3 (NSE), Phase 4 (CallKit and call audio session).

Exit criteria: seven distinguishable, consistently normalized sounds play correctly on Fedora, iOS, and Android; in-app chimes never glitch a live call; reduce-motion collapses non-essential motion; the polish pass has no known visible defects in the primary flows.

## Phase 9 - Release Readiness and Store Submission

Size: M.

Objective: finalize compliance, deployment simplicity, and the 1.0 release across all supported channels.

Deliverables:

- App Store and Play compliance closeout: 18+ rating plus Play IARC, always-visible account deletion/report/block, terms-of-use gate, VoIP entitlement with the CallKit invariant test, screen-share permissions, privacy nutrition labels with the self-hosted-server publisher-visibility disclaimer, App Review notes, and a standing demo self-hosted deployment.
- Finalized production docker-compose (server, postgres tuned, Caddy, LiveKit) with a well-documented one-command deployment, backup story (self-host scripted pg_dump plus attachment tarball; official WAL archiving with restore drills), and a documented Traefik fallback.
- Linux artifacts (AppImage primary, rpm alongside) and the iOS TestFlight-to-production path, all signed with cosign, SLSA provenance, GPG, and SHA256SUMS, and the official-instance explicit deploy-on-release-merge step.
- Flathub/OARS noted as tracked future scope.

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
The design track (validating the palette against the CI contrast gate and a designer review) runs in parallel from Phase 0, since the token pipeline and gate exist from the start and the visual identity is decoupled from widget code by design.
