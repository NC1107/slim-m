# Echo Messenger - Reference Notes

Repository: `decentralized-chat-app` (product name: echo-messenger).
Rust server + Flutter client, encrypted cross-platform chat app.
These notes focus hardest on the Voice Canvas (voice-lounge whiteboard) feature, both server and client, and summarize the wider architecture around it.

## 1. Overall architecture and tech stack

### Stack

- Server: Rust, Axum for HTTP + WebSocket, SQLx against PostgreSQL.
- Client: Flutter (Dart), Riverpod for state management (code-generated with `riverpod_annotation`), GoRouter for navigation.
- Shared crypto core: `core/rust-core/` - Signal Protocol primitives (X3DH + Double Ratchet) written in Rust.
Important nuance: the originally-planned FFI bridge from Dart to this Rust core never landed.
The Dart client re-implements the Signal Protocol in pure Dart (`signal_protocol.dart`, `signal_x3dh.dart`, `signal_session.dart`).
The Rust core is exercised only by Rust integration tests, not by the shipping app.
This is a live "dual implementation" design question, tracked in `docs/crypto-audit/05-rust-core-vs-dart.md`.
- Local client storage: Hive for offline message cache and app state, `flutter_secure_storage` for private keys (platform keystore), `SharedPreferences` for settings.
- Voice/video: LiveKit (SFU-based WebRTC), not the originally-researched raw P2P WebRTC.
- Deployment: Docker Compose + Traefik, three compose files (dev, CI, prod). GHCR image registry, watchtower auto-updates production.

### Workspace layout

- `apps/server/` - Axum server.
Key modules: `auth/` (JWT 15-min access + 7-day refresh, Argon2id, `AuthUser` extractor), `ws/hub.rs` (DashMap of `user_id -> mpsc::Sender` for lock-free routing), `ws/handler.rs` (WS upgrade + dispatch), `db/` (query modules per entity), `routes/` (REST endpoints).
- `apps/client/` - Flutter app. `lib/src/screens/`, `lib/src/providers/` (Riverpod), `lib/src/widgets/`, `lib/src/services/`, `lib/src/models/`.
- `core/rust-core/` - shared Signal Protocol primitives (Rust-only consumer today; see above).

### Server startup sequence (main.rs)

Load `.env` → tracing init → create upload dirs → `Config::from_env()` → Postgres pool + auto-migrate SQL files (14 migrations at time of writing) → spawn WS Hub (DashMap) → spawn background tasks (stale voice-session cleanup every 60s, empty-group cleanup) → build Axum router → bind with graceful shutdown.

### WebSocket protocol

- Auth is ticket-based only: client calls `POST /api/auth/ws-ticket` to get a 30-second single-use ticket, then connects `wss://.../ws?ticket=...`.
JWT is never placed in the WS URL.
- Heartbeat: server pings every 30s; client treats no traffic for 60s as a dead connection and reconnects.
- Reconnect: exponential backoff with 0-50% jitter, capped at 60s, up to 1000 attempts (effectively unlimited). Implemented in `websocket_provider.dart` / `websocket/websocket_lifecycle.dart`.
- Wire format: JSON frames (not protobuf, despite early architecture docs suggesting protobuf - the actual implementation uses JSON `type` and per-event fields).
- Message wire format for E2E payloads is binary and base64-wrapped: Initial V2 (with one-time prekey) = `[0xEC,0x02] + identity_pub(32) + ephemeral_pub(32) + otp_id(4 LE) + ratchet_wire`; Initial V1 = same without otp_id; Normal = `header_len(4 LE) + header(40) + nonce(12) + ciphertext + tag(16)`.

### Sync / ordering model (general messaging, not canvas)

- Soft deletes via `deleted_at TIMESTAMPTZ NULL`, filtered at query time; hard delete only for disappearing-message TTL cleanup and cascade group deletion.
- Multi-device: key-level revoke + last_seen + platform metadata works; refresh tokens are not yet bound per device, so "logout all others" only kicks currently-connected WS sessions, not truly offline ones.
- Group E2E ("GRP2" design: Sender Keys + server-led leader election + per-message sender signatures) is designed but not fully wired; group messages currently hard-fail on encryption error rather than falling back to plaintext when `is_encrypted=true`.

### Architecture docs vs reality

The `architecture/` directory (`system_design.md`, `tech_stack.md`, `networking.md`) reads as an early planning document (mentions Go-or-Rust server choice, protobuf wire format, NATS/Redis Streams, MLS for >1000-member groups, federation phase 3).
Much of this is aspirational/historical rather than current: the shipped server is Rust/Axum with JSON WS frames, no NATS/Redis in evidence in the code read, no federation implemented.
Treat `architecture/*.md` as "original design intent," and `CLAUDE.md` + `docs/voice-lounge/*` + `TECHNICAL_DEBT.md` as "current ground truth."

## 2. Voice Canvas - what it is

The voice lounge is a per-voice-channel collaborative whiteboard shown alongside a LiveKit voice/video call: participants can freehand-draw, drop shapes/text/images, and see each other's avatars as draggable pucks on a shared 2D board.
It is one of the most heavily audited and iterated subsystems in the codebase (see the `docs/voice-lounge/` decision-of-record folder, described below).

### Data model (server: `apps/server/src/db/canvas.rs`)

- One row per voice channel in a `channel_canvas` table (created lazily on first write): `channel_id`, `drawing_data JSONB` (array of stroke objects), `images_data JSONB` (array of image objects).
- Avatar positions are NOT persisted server-side - they are pure ephemeral WS broadcasts, reset on rejoin.
- Screen-share window positions are likewise ephemeral, never persisted.
- Hard caps: `MAX_STROKES = MAX_IMAGES = 2000` per channel, enforced with a `SELECT ... FOR UPDATE` row lock + append inside the same transaction (fixed a real TOCTOU race where two near-simultaneous appends could both pass a naive count-then-insert check).
There was also a real production bug where `jsonb_array_length` decodes as `i32` not `i64`; decoding it as `i64` silently classified every cap-check as a DB error, which silently dropped every stroke after the first for late joiners - fixed by decoding as `i32` and widening at compare time.
- Authorship stamping: every persisted stroke/image gets a `from_user_id` field stamped server-side (`stamp_author`) so a later `clear(scope: "mine")` can filter by author.
Entries persisted before this existed have no `from_user_id` and are treated as "unowned" (never deleted by a scoped clear), a deliberate safety choice over guessing ownership.
- `update_image` rewrites the *entire* `images_data` JSONB array via `jsonb_agg` - flagged as write-amplification technical debt (see below).
- `get_canvas` returns the whole board unpaginated in one REST response - flagged as a scaling problem once near the 2000-item cap.

### Coordinate system (client: `apps/client/lib/src/models/canvas_models.dart`)

- The canvas is a **fixed, bounded** square surface, not infinite.
Its size has moved multiple times: 100,000px → 4096px → 6000px (`kCanvasWidth = kCanvasHeight = 6000` today).
This is explicitly called out in the architecture assessment as "the unresolved canvas-size problem" - Miro/Figma-style products are infinite/tiled; this one is a fixed box with gesture clamping.
- Strokes and avatars live in this canvas-world absolute-pixel coordinate space, so every device draws the same stroke in the same logical place regardless of viewport size; only pan/zoom differs per device.
- Screen-share windows are the one entity that historically lived in viewport-relative CSS pixels, which caused a real cross-device bug (sender's 1920×1080 pixel position snapped to the edge of a receiver's 390px-wide phone).
The fix (documented decision, `01-coordinate-policy.md`) was to normalize screen-share coordinates to `[0,1]` of the sender's interactive viewport (`x_norm/y_norm/w_norm/h_norm`, with a `coord_v` version field so legacy raw-pixel payloads keep working through a translation shim). A 120px minimum is enforced on the receiving side so a small phone viewport can't shrink a shared window below readable size.
- There is a legacy-coordinate migration heuristic (`_migrateLegacyCoord`): any value `<= 1.0` is treated as an old-style 0..1-normalized coordinate and multiplied by 4096 (not by the current 6000/100000 constant - deliberately kept at the historical scale so old drawings don't get scattered).
A session counter tracks how often this heuristic fires, logged once per session, with an explicit documented removal gate (14 consecutive days with zero fires across at least 5 distinct users) before the code gets deleted. This is a good pattern for safely retiring migration shims.

### Object model - what's missing

There is no real object model. A "board" is two flat, append-only JSON arrays.
There is no z-order, no affine transforms/rotation, no grouping, no multi-select, no undo/redo, no connectors, and no per-object identity beyond an id string.
The June 2026 architecture assessment (`07-canvas-architecture-assessment.md`) explicitly names this as a dead end for reaching Figma/Miro/draw.io-level functionality and recommends replacing it with a per-object table: `canvas_objects(channel_id, object_id, type, z, transform, props JSONB, seq)`. This is Phase 2 of a 4-phase recommended rewrite (see Section 6).

## 3. Sync and authority model

### Event kinds (WS)

Canvas events travel over the existing WebSocket connection as a generic `canvas_event` frame: `{type: "canvas_event", channel_id, kind, payload}`.
Valid `kind` values (`apps/server/src/ws/events/canvas.rs`):
- `stroke` - a completed freehand/shape/text stroke. Persisted.
- `stroke_partial` - live in-flight preview points while a peer is mid-drag. Ephemeral, never persisted, capped at 200 points server-side (vs 5000 for a full committed stroke).
- `clear` - wipe the board (or, with `scope: "mine"`, just the sender's own content). Persisted (applies to stored state).
- `image_add` / `image_move` / `image_remove` - persisted, with `image_move` carrying a `commit: false/true` flag so intermediate drag frames are relay-only and only the pointer-up frame triggers a DB write (this was a real perf fix, #1339, for write-amplification during drags).
- `avatar_move` - ephemeral, relay-only, never persisted. Keyed by `user_id`, not `device_id` (see multi-device below).
- `screenshare_move` - ephemeral, relay-only, never persisted, dual wire format during the coord_v migration.
- `canvas_authority_claim` - explicit device-authority handoff (see below); never persisted or relayed as a `canvas_event`, it triggers its own `canvas_authority_changed` broadcast instead.

### No CRDT, no sequence numbers - the acknowledged consistency gap

This is probably the single most important lesson from this codebase: canvas sync today is "per-event relay-and-persist" with **no sequence numbers, vector clocks, operational transform, or CRDT**.
Clients apply events strictly in the order they are *received* over the WebSocket, which can differ from client to client.
The June 2026 architecture assessment names concrete, real divergence paths:
- Concurrent image-move race (relay order can differ from persist order).
- Stroke-partial reordering.
- "Clear resurrection": a stroke committed by peer B just before B processed peer A's `clear` can still arrive at A *after* A's clear and reappear (tracked as issue #1328 / "VL-6"). The client has a partial defensive fix - a local `clear` aborts any of *your own* in-flight stroke so your own pending `endStroke` can't resurrect content on a just-cleared board - but this doesn't fix the cross-peer race the issue describes.
- Late-joiner mid-fetch double-apply.
- Multi-device authority skew.
- Lost ephemeral events on reconnect.

The documented, scoped smallest fix (no CRDT library needed) is a server-assigned monotonic `seq` on every persisted op, with clients ordering by `seq` and late joiners fetching `last_seq` then replaying from there - LWW-by-seq for conflicts. This is Phase 1 of the recommended rewrite roadmap and has not shipped as of the last audit (2026-06-10).

### Server-side validation (`canvas_validation.rs`)

Pure, well-tested per-`kind` schema/geometry validators: bounded coordinate ranges (`-1000..110000`, with a hard `100000` surface cap), bounded stroke point-array length (5000 for full strokes, 200 for partials), bounded stroke width (`<=200px`), hex-color format checks, UUID-shape checks, tool-name allowlist, and a UUID-based media-reference extractor for `image_add` URLs.
Notably this validation ships behind a three-state rollout flag (`CANVAS_VALIDATION_MODE = off | log_only | enforce`, default `log_only`), read once via `OnceLock` at process start.
The stated rollout plan: run `log_only` for ~2 weeks in production, grep logs for `canvas.validation.*` codes to confirm no legitimate client trips a false positive, then flip to `enforce`.
This is a deliberate, cautious pattern for shipping new server-side validation on an existing wire protocol without an immediate hard cutover risk - worth reusing in a rebuild.

Order of operations in `handle_canvas_event` matters and is deliberately structured: (1) validate the `kind` string against an allowlist, (2) resolve the channel and verify group membership *before* running the schema validator, specifically so an unauthenticated-for-this-channel client can't use validation error codes as an oracle to probe payload shapes or burn CPU, (3) run per-kind validation, (4) handle `canvas_authority_claim` as its own short-circuit path, (5) gate writes through the authority check, (6) persist, (7) broadcast to all other conversation members except the sending device.

### Canvas authority (multi-device-per-user model)

Documented decision in `03-multi-device.md` (Option C, chosen over per-device avatar duplication or plain last-write-wins).
Avatars are keyed by `user_id`, not `(user_id, device_id)` - a user's two simultaneous devices (desktop + phone in the same lounge) share a single avatar slot.
To prevent both devices' input fighting over that slot, the server tracks an in-memory-only `(user_id, channel_id) -> device_id` map (`canvas_authority.rs`, backed by a `DashMap`, no DB persistence - a server restart or the user leaving the lounge wipes it and the next writer implicitly reclaims).

Rules:
- First writer from a user's devices implicitly claims authority (`claim_if_absent`); no explicit claim event needed.
- A device can explicitly request authority by sending `canvas_authority_claim` (empty payload); the server grants it unless the *current* holder claimed within the last 1 second (`CLAIM_GRACE`), which exists specifically to stop a rapid double-tap from two devices oscillating authority back and forth.
- Non-authority devices' writes (`stroke`, `image_*`, `avatar_move`) are **silently dropped** server-side - no error response - specifically so a "rogue" (stale-authority-believing) device doesn't retry-storm the server.
- Authority changes broadcast a `canvas_authority_changed {channel_id, user_id, device_id}` event to *every* lounge member (not excluded from the sender), so the user's own other devices learn to flip into read-only mode and other participants can render a "Drawing from <device>" pill.
- Authority is strictly per-lounge; joining a second lounge starts a fresh authority race even if a device already held authority elsewhere.
- Known open gap at the time of the last audit: the broadcast that excludes "the sender" was excluding by *user_id* rather than *device_id*, meaning a user's own read-only second device could miss the authority device's live strokes entirely (issue #1333 / VL-19). The `canvas.rs` handler code as currently read *does* correctly exclude by `sender_device_id` (`broadcast_json_except_device`), so this specific bug appears fixed in the reviewed revision, but it's a good example of the device-vs-user-id class of bug this codebase repeatedly hit.

### Encrypted-group canvas - real, disclosed privacy gap

Canvas events are **plaintext**, on the wire and at rest, in every group including groups where 1:1/group *messages* are end-to-end encrypted via the Signal Protocol / GRP2 design.
This is a deliberate, disclosed decision (`04-encrypted-canvas.md`, Option A short-term / Option B medium-term): ship a one-time popup + a `docs/PRIVACY.md` disclosure now, defer real encryption (reusing the GRP2 group sender key once that infrastructure exists for messages) to a tracked follow-up (#1268) gated on "GRP2 message E2E shipped to prod."
Notable: even after that follow-up ships, server-side metadata (group_id, sender_user_id, timestamp, event kind) stays visible - that's named as the inherent floor of any relay-based (non-P2P) architecture - and the uploaded image *bytes* referenced by `image_add` remain unencrypted at rest regardless, since that needs a separate per-group media-key design.

## 4. Client rendering approach

### History: from InteractiveViewer to an explicit gesture state machine

The canvas originally used Flutter's `InteractiveViewer` for pan/zoom plus a separate `GestureDetector`-based drawing overlay, arbitrated implicitly via gesture-arena "slop" heuristics (an ~18px dead zone before a stroke would "win" against the pan recognizer).
This produced a long tail of hard-to-fix bugs: double-tap-zoom firing mid-stroke, pinch fighting an in-progress stroke, and generally "the canvas feels bad on mobile" reports.

A full rewrite (`05-canvas-rewrite-spec.md`, dated 2026-05-28, shipped and confirmed good in the later architecture assessment) replaced this with:

1. **Explicit pointer-count-driven state machine** (`canvas_gesture_state.dart`) - pure, dependency-free transition logic (`CanvasGesturePhase`: `idle | drawing | panning | pinching`), unit-testable without a widget tree.
Transitions are driven purely by pointer count and whether a draw tool is selected, never by slop/arena races: 1 pointer + tool selected → drawing; 1 pointer + no tool → panning; 2nd pointer while drawing → pinching *and cancels the in-flight stroke*; 2nd pointer while panning → pinching (no cancel needed); dropping to 1 pointer while pinching → idle (deliberately does not fall back into single-pointer pan - next gesture starts clean).
2. **A single root `Listener`** (`lounge_canvas_gestures.dart`), not a `GestureDetector`, owning the `Matrix4` transform directly and feeding raw pointer events into the state machine. This is the widget-level implementation of the above transition table, plus double-tap-zoom (gated off while a tool is active), pan-margin clamping (15% of content always stays on-screen), and a `CanvasDragScope` inherited widget so child drag gestures (dragging an avatar or image) can suppress the parent's pan logic via a reference-counted suppress/release pair - this exists because the root `Listener` always sees pointer-move events even when a child `GestureDetector` wins the arena for its own drag, so without the scope both the canvas pan and the child drag would apply simultaneously and roughly cancel out (avatars appeared "stuck").

### Three-layer RepaintBoundary painting

`lounge_canvas_strokes.dart` splits rendering into three independently repainting layers, which is the single biggest perf lesson in this codebase:
- L0 background (grid/mesh/theme image) - its own `RepaintBoundary`.
- L1 committed strokes + images + avatars - repaints only when the committed strokes list identity changes (`shouldRepaint` does an `identical()` check, not deep equality - cheap and correct because the provider always replaces the list on mutation).
- L2 in-flight (local) stroke only - repaints on every pointer-move tick.

The critical mechanism: the in-flight stroke is **not** stored in Riverpod state at all during the drag.
It lives in a plain `ChangeNotifier` (`ActiveStrokeNotifier`), and the L2 `CustomPaint` is wired directly to that notifier via `repaint:`.
Before this rewrite, every pointer-move called `state = state.copyWith(activePoints: pts)`, which rebuilt every Riverpod consumer of canvas state - the entire committed-strokes painter, the toolbar, perf counters - on every single sampled point, at up to 30Hz.
The fix bypasses the state-management layer entirely for the hot path and only touches Riverpod state on `startStroke`/`endStroke`.
This "hot-path data does not have to live in your state-management system" pattern is directly reusable in any canvas/whiteboard rebuild.

Stroke smoothing uses the `perfect_freehand` package (same algorithm Excalidraw uses) to turn a raw polyline into a tapered, velocity-thinned filled outline; the wire format stays raw points (smoothing is purely a local rendering concern, so it has zero effect on sync or encryption).
Committed strokes memoize their computed outline `Path` in an `Expando` keyed by stroke-instance identity, so a remote peer's live drawing (which mutates the committed-strokes list ~30x/sec by replacing a placeholder stroke) doesn't force every *other* static stroke on the board to re-run the perfect_freehand tessellation every frame - only the mutated stroke recomputes.

### Draggable/resizable items and grid background

`draggable_canvas_item.dart` provides a shared drag/resize frame reused by both images and screen-share windows.
`canvas_grid_background.dart` implements an adaptive 1-2-5×10ⁿ ruler grid, explicitly called out in the architecture assessment as "genuinely Figma-grade" - one of the few pieces judged good enough not to touch in a rewrite.

### Product-identity conflation (a named design smell)

The June 2026 assessment names a real design problem: avatars (voice presence), whiteboard content (strokes/shapes/text), and screen-share windows all currently share one coordinate space and one authority model on the same canvas.
Reference products (Figma/Miro/draw.io) treat presence as a roster/overlay, never as a canvas object.
The documented Phase 0 product decision (2026-06-10) is "whiteboard-first": demote avatars from canvas objects to a roster/overlay, decoupled from canvas coordinates and canvas authority.
This has been decided but not yet implemented (it is Phase 4 of the roadmap, after the sync and object-model phases).

## 5. Voice / LiveKit integration

- Server (`apps/server/src/routes/voice.rs`) mints short-lived LiveKit JWTs (`POST /api/voice/token`).
Deliberately short TTL (5 minutes, down from an original 1 hour) specifically because the server has no LiveKit management-API client wired to force-evict a participant, so a kicked/banned member's already-minted token remains valid (and thus their SFU publish ability remains live) until it expires - the short TTL bounds that exposure window rather than closing it. A related open issue (#1330) notes the grant is still uniform full-publish for every member including listener roles, not yet role-scoped.
- Room name is derived server-side from the conversation UUID (not client-supplied), specifically to prevent a client from steering their grant to a room/conversation they aren't a member of - an explicitly called-out fix for a prior cross-room escalation bug.
- LiveKit participant identity is `username` or `username#<8-hex-nonce>` (nonced to avoid SFU identity collisions on rapid rejoin within LiveKit's ~15s participant-idle window, which otherwise caused `setMicrophoneEnabled` to time out) or the raw user_id; the server validates the identity shape server-side to prevent impersonation.
- Client-side (`livekit_voice_provider.dart`, ~1200 lines) is a Riverpod notifier wrapping the `livekit_client` package: join/leave lifecycle, mic/camera/deafen state, per-peer audio levels, active-speaker set (pushed via LiveKit's `ActiveSpeakersChangedEvent`, faster than polling), connection-quality badge, RTC stats polling for bitrate/RTT, and platform integration (CallKit on iOS, a foreground service on Android, push-to-talk).
- A documented, fixed crash class: `leaveChannel` guards against re-entrancy with an `_isLeaving` latch and every room-event handler checks a `_disposed` flag, because concurrent leave triggers (UI tap, Android foreground-service `ACTION_LEAVE`, iOS CallKit hang-up) used to race and throw `StateError` after `ref` was disposed. See the lifecycle audit below.
- Known test gap (issue #1329): the join/leave/rejoin race in `LiveKitVoiceNotifier` has no execution test because it needs a `Room`-injection seam (join currently always creates a real LiveKit `Room` and touches native mic permissions/CallKit) that doesn't exist yet.

## 6. Top five lessons a rebuild should learn

1. **Decide the sync/consistency model before shipping collaborative real-time state, not after.** This codebase shipped a genuinely excellent gesture/rendering layer (state machine, RepaintBoundary layering, stroke smoothing) on top of a sync layer with no ordering guarantee at all - plain "apply events in WebSocket receive order." That gap produces real, user-visible divergence bugs (clear-resurrection, image-move races, late-joiner double-apply) that no amount of client-side polish fixes. A rebuild should pick a documented ordering strategy (a server-assigned monotonic sequence number per persisted op is the cheapest one that solves most of it, no CRDT required) as an early architectural decision, not a "Phase 1 follow-up" bolted onto a shipped feature.

2. **Do not model a growing collaborative document as two flat append-only JSON blobs with a hard cap.** The `drawing_data`/`images_data` JSONB-array-per-channel model hit real, predictable walls: a 2000-item cap with silent-reject-on-overflow, full-array rewrites on every single-object update (`jsonb_agg` over the whole array), and an unpaginated single-response fetch that becomes a multi-MB payload at the cap. None of select/move/resize/group/undo/redo/z-order is addable inside that model. If you know the target is a real object canvas, start with a per-object row (id, type, z-order, transform, props, sequence) - it costs little more up front and avoids a full-scale migration later.

3. **Bound coordinate spaces are a coordinate-space leak waiting to happen; decide per-entity whether something is "world content" or "viewport overlay" up front.** The screen-share cross-device bug (sender's raw CSS-pixel position snapping to the wrong place on a differently-sized receiver viewport) happened because one entity type quietly used device-local pixels as if they were a universal coordinate, while everything else used a shared canvas-world space. The fix (normalize overlay-type entities to `[0,1]` of the sender's own viewport, keep world-content entities in absolute shared-canvas coordinates) is the right general rule, but it's much cheaper to apply from day one than to retrofit with a wire-format version field and a legacy-payload translation shim.

4. **Hot per-frame interaction data does not belong in your global state-management system.** Piping every pointer-move sample through `state = state.copyWith(...)` (Riverpod, but the lesson generalizes to Redux/MobX/whatever) rebuilds every consumer of that state on every sample - here, that meant the whole canvas repainting at up to 30Hz during a single stroke. The fix - a narrow, purpose-built `ChangeNotifier` that only the active-stroke painter listens to, completely bypassing the app's state management for the duration of the gesture - is a pattern worth designing in from the start for any canvas/whiteboard/drag-heavy UI, rather than discovering it as a performance-driven rewrite.

5. **Write down interaction contracts before they're "obvious," and keep them living.** The `docs/voice-lounge/` folder (coordinate policy, input matrix per device class, multi-device authority, encrypted-canvas trust posture, the rewrite spec itself) is unusually good practice: each doc has status-quo-with-citations, options with pros/cons, a dated decision, testable acceptance criteria, and explicit open questions with a stated pickup trigger. The project's own rule - a PR that changes documented gesture/sync/coordinate behavior must update the doc first, in its own PR - is exactly the discipline that prevented a second wave of the ad-hoc, slop-driven bug class the original gesture-arena implementation suffered from. A rebuild should budget for this kind of living decision record from the start, especially for anything involving multi-device semantics, gesture arbitration, or wire-format versioning, since those are exactly the areas where "just fix the bug" patches accumulate into unreadable, contradictory logic over time.

## Sources read (file:line references throughout this document trace back to)

- `CLAUDE.md` (repo root)
- `README.md`, `architecture/{system_design,tech_stack,networking}.md`
- `docs/voice-lounge/{README,01-coordinate-policy,02-input-matrix,03-multi-device,04-encrypted-canvas,05-canvas-rewrite-spec,06-lifecycle-audit-2026-05-28,07-canvas-architecture-assessment,perf-baseline}.md`
- `TECHNICAL_DEBT.md` (voice-lounge canvas rearchitecture section + issues #1268, #1285, #1328–#1333)
- `apps/server/src/routes/canvas.rs`, `apps/server/src/routes/voice.rs`
- `apps/server/src/ws/events/canvas.rs`, `canvas_authority.rs`, `canvas_validation.rs`
- `apps/server/src/db/canvas.rs`
- `apps/client/lib/src/models/canvas_models.dart`
- `apps/client/lib/src/providers/canvas_provider.dart`, `canvas_authority_provider.dart`
- `apps/client/lib/src/providers/websocket_provider.dart` + `websocket/*.dart`
- `apps/client/lib/src/providers/livekit_voice/livekit_voice_provider.dart`
- `apps/client/lib/src/widgets/voice_lounge/canvas_gesture_state.dart`, `lounge_canvas_gestures.dart`, `lounge_canvas_strokes.dart`
- Test file inventory under `apps/server/tests/*canvas*` and `apps/client/test/**/*canvas*` (confirms real, extensive coverage of the above; not individually read in depth)
