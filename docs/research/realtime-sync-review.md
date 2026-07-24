# Realtime Sync and Messaging Protocol Plan: Adversarial Review

Target document: `docs/research/realtime-sync.md`.
Cross-checked against `docs/BRIEF.md`, the sibling reports in `docs/research/` (`backend.md`, `database.md`, `security.md`, `voice-canvas.md`, `performance.md`, `networking-relay.md`), the echo-messenger reference notes (`decentralized-chat-app/reference-echo-messenger.md` and `decentralized-chat-app/CLAUDE.md`), and the check-in-relay reference notes (`check-in-relay/reference-check-in-relay.md`).

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The push-trigger "live WS connection" check does not match how iOS actually suspends backgrounded apps

The plan's push-trigger logic is: after an event is fanned out, check whether each recipient device has a live WS connection, and only push to devices that do not.
The gateway lifecycle section sets the liveness signal at a 30s heartbeat with a 60s client-reconnect threshold, and a 90s resume window during which the hub still tracks the session.
On iOS, a backgrounded app without a special background mode (VoIP, background audio, etc.) is suspended by the OS well before either of those windows elapses, so the process cannot run any Dart code to receive, decrypt, or display anything arriving over an already-open socket.
The TCP connection itself is not necessarily torn down the instant the app suspends; it can sit idle, unacknowledged, and still present in the hub's connection registry until the heartbeat or reconnect timeout eventually notices it is dead.
Concrete failure: user A backgrounds the app, user B sends a message ten seconds later, the server sees user A's connection as "live" (no heartbeat has failed yet) and suppresses the push, but user A's OS has already suspended the process, so the WS frame is never processed and no local notification fires.
The message becomes silently undeliverable until the next foreground open or the next heartbeat failure forces a reconnect, which can be tens of seconds away.
This is not a narrow edge case: it is the exact scenario the brief calls out as the reason the relay exists at all ("mobile applications cannot reliably receive incoming connections or maintain persistent connections while backgrounded").
`networking-relay.md`'s own wake-push design shares the same blind spot, since it also gates the "wake" push kind on "the WebSocket is not already live," so this is a design gap shared across two sibling reports, not a typo in one.
Fixing this requires the push-trigger decision to use an explicit client-reported lifecycle signal (foreground and backgrounded and terminated) rather than raw socket presence, or a push-trigger-specific liveness check with a much tighter timeout than the general-purpose 30s or 60s heartbeat, and that is a real redesign of the push-trigger decision, not a constant tweak.

### 2. The flat 20 canvas-ops/s rate limit conflicts with the canvas's own continuous relay-only drawing traffic

`realtime-sync.md`'s rate-limiting section sets a single number, 20 canvas ops/s per user per channel, with no distinction between persisted, discrete ops (a completed stroke, an image add) and ephemeral, high-frequency relay-only preview frames (`stroke_partial`, `avatar_move`, in-flight `image_move` with `commit:false`).
`voice-canvas.md`, the sibling report that owns the canvas feature, targets "steady-state WS traffic per actively-drawing user under 20KB/s," which is only achievable with a continuous stream of small preview frames sent far more often than 20 per second, and echo-messenger's own precedent mutates the committed-strokes list roughly 30 times per second during a single drag.
Applying the stated limit literally means any user actively dragging a stroke for more than about one second exceeds the cap and starts receiving the plan's own specified `retry_after_ms` error frames mid-gesture, which is a visible stutter or an outright dropped stroke in the app's flagship feature, not an abuse scenario.
The plan does acknowledge canvas needs its own silent-drop semantics for stale non-authority writes, so it is aware canvas traffic is different in kind, but the numeric rate limit itself was not adjusted to match.
The fix is a genuine redesign of this limit into at least two classes: a low, strict cap on persisted ops, and either a much higher cap or a bytes/sec throttle (matching the 20KB/s budget already set elsewhere) on ephemeral relay-only frames, not a single events/sec number applied uniformly.

### 3. The 64-bit snowflake ID has no reserved node or shard bits, which blocks horizontal scaling without a breaking migration

The plan describes the ID as "timestamp plus in-process counter" only.
No bits are set aside for a machine or node identifier, which is the standard reason snowflake-style schemes reserve space for it from the first ID ever issued, even when only one process exists on day one.
`realtime-sync.md`'s own open questions ask whether the official instance's WS-hub and rate-limit state should move to a shared store "on day one, or only when horizontal scaling actually becomes necessary," and `database.md` separately flags that "if [the official instance runs more than one application-server process], snowflake ID generation needs an assigned node-id range per process, a small addition, decided before launch, not retrofitted."
As specified, that addition is not small: because no space was reserved, adding a node identifier later means shrinking either the timestamp or counter portion of an ID format that has already been used as a primary key, referenced by clients for local-echo reconciliation, and embedded in every sync cursor, so a later fix either breaks the sort-order guarantee for already-issued IDs or requires a parallel ID-version scheme.
This directly conflicts with the brief's "future scalability" goal for the database layer and with the plan's own stated uncertainty about whether the official instance stays single-process.
The fix (reserving a small node-id field, defaulting to zero on self-hosted single-process deployments) costs nothing today and should be specified now, not left implicit.

## Major findings

### 4. The 90s resume-session state appears to duplicate the stateless catch-up endpoint it is described as using

The gateway lifecycle section adds a stateful, in-memory, per-connection session record (`session_id`, `last_sent_id`) that survives 90 seconds after disconnect, with its own sizing risk ("too short reduces resume value, too long grows memory per stalled session").
The same section then says a reconnecting client "replays only the gap via the same mechanism used for cold-start catch-up," which is the stateless `GET /api/sync?after=<id>` cursor endpoint the client already needs for ordinary offline catch-up.
If resume and cold-start use the identical mechanism, the client already carries everything it needs to catch up on any reconnect, resumed or not, since it must already track its own last-received ID locally to call that endpoint at all.
Nothing in the plan states what capability the server-side session record adds over a client that always calls the sync cursor on every reconnect: no faster in-memory replay path is described, no re-authentication skip is described, only the same DB-backed query.
As written this reads as maintained server state (with its own sweep policy and a tuning knob later flagged as "a guess") solving a problem the plan's own catch-up design already solves for free, which is exactly the kind of unrequired complexity the brief warns against for a self-hosted, lightweight default.
Either the resume path needs a stated, concrete benefit over stateless reconnect-and-resync, or it should be dropped in favor of always using the sync cursor.

### 5. The WS auth story is inherited from echo's JWT model even though this project's security report rejects JWTs

The gateway lifecycle section states the connect flow almost verbatim from echo-messenger: "REST login issues a 30-second single-use WS ticket... JWT never touches the URL."
`security.md`, the report that owns this project's authentication decision, states the opposite verdict for the underlying credential: "opaque server-side session tokens, not stateless JWTs," specifically to get instant per-device revocation, which the brief's admin and device-management goals depend on.
A short-lived, single-use, off-URL ticket works equally well whether the credential behind it is a JWT or an opaque session token, so the ticket mechanism itself is not wrong, but the plan never says which one it mints the ticket from, and the sentence it borrowed from echo only makes sense if a JWT exists to keep out of the URL in the first place.
Left as written, a reader implementing this section from `realtime-sync.md` alone would build the wrong credential type and lose the revocation property `security.md` already committed to.
`database.md` shows the discipline this report should have followed: when it reused `realtime-sync.md`'s own snowflake ID over `voice-canvas.md`'s per-channel counter, it said so explicitly and gave the reason.
This section needs the same explicit reconciliation with `security.md`'s token model, not a copied sentence from a different project's auth design.

### 6. E2E-conversation handling is described as current v1 scope, but the security report defers E2E to a later opt-in feature

The wire-format section frames base64-wrapped ciphertext as a present-tense need ("Binary payloads (E2E ciphertext) stay base64 strings inside it"), and the push-triggering section designs a full content-free wake-push path "for E2E-encrypted conversations."
`security.md`'s verdict is that v1 ships transport encryption only, with end-to-end encryption "explicitly deferred, not adopted," and `database.md`'s schema reflects that by giving `messages.content` a plaintext default with an `is_encrypted` escape hatch for a future feature, not a live one.
Nothing about designing the wire format and push path to be E2E-ready is wrong on its own, forward-compatible design is good practice, but the report presents this as an existing routing concern rather than a documented accommodation for a feature that does not exist in v1, which risks a reader treating E2E DM handling as in-scope work for the initial build.
This should be reframed explicitly as "pre-wired for a future feature per `security.md`," matching the reconciliation discipline `database.md` already modeled elsewhere in this same research pass.

### 7. The unified sync cursor's `canvas_op` kind is not reconciled with the canvas report's separate join-time fetch protocol

`realtime-sync.md` proposes that a reconnecting or catching-up client replays canvas history through the same global, chronologically ordered `GET /api/sync?after=<id>&kinds=...,canvas_op` cursor used for messages and reactions.
`voice-canvas.md` independently specifies a different mechanism for the same need: late joiners "fetch current materialized state, keyset-paginated by seq, viewport-first," a snapshot-plus-viewport model, not a chronological op replay.
Chat messages and reactions are append-only, so replaying them in received order is always safe, but canvas ops include destructive operations (`clear`, object deletion) that echo's own reference notes document as the source of real divergence bugs when replayed naively (the "clear-resurrection" case).
The plan does not say whether a client reconnecting mid-session should apply raw `canvas_op` deltas from the global cursor directly on top of its last-known canvas state, or discard them and re-fetch a fresh materialized snapshot from the canvas-specific endpoint instead, and those two choices require different client logic and give different consistency guarantees.
This is a second, distinct catch-up mechanism for canvas data sitting next to the one `voice-canvas.md` already specifies, and the two are not reconciled anywhere in either report.

### 8. The 256-message bounded channel size is not checked against the canvas's own worst-case fan-out

The gateway lifecycle section bounds each connection's outbound channel at 256 messages and closes the connection on overflow, framed as protection against one wedged client.
That same channel also carries canvas fan-out, and finding 2 above establishes that a single actively-drawing user can legitimately emit well more than 20 events/s of relay-only preview traffic; a multi-participant canvas session fans that out to every other connected device in the channel.
A receiver on a slower or lossy mobile link only needs its outbound send to lag briefly during a burst from several simultaneously drawing peers for the 256-slot buffer to fill, at which point the plan's own design closes that user's connection rather than dropping or coalescing the stale ephemeral frames.
The practical effect is repeated forced disconnects for exactly the participants on weaker connections during the highest-value moments of the feature the brief calls out as its defining one.
The number needs to be sized against the rate-limit fix in finding 2, or the overflow policy needs to coalesce or drop superseded ephemeral events (a newer `avatar_move` supersedes an older one for the same actor) before falling back to closing the connection.

## Minor findings

### 9. A third, unreconciled idle-RSS figure is introduced for the same server process

`backend.md` sets the server process idle RSS budget at under 30MB.
`voice-canvas.md` separately states 150MB "for the whole process," a conflict `performance.md` already caught and proposed to resolve by relabeling the 150MB figure as a light-activity ceiling rather than a true idle baseline.
`realtime-sync.md` adds a third figure for what is the same process, "an idle self-hosted gateway process (handful of users) should stay well under 50MB RSS," without referencing either the 30MB baseline or `performance.md`'s reconciliation note.
This does not contradict either existing number outright since "well under 50MB" is compatible with a 30MB baseline, but it is a third independently chosen number for a metric the project has already had to reconcile once, and it should point at the existing 30MB figure rather than restating a new one.

### 10. The unread-count query shape is asserted, not shown, for a user in many conversations

The read-state section states the unread count is "computed once inside the sync-summary query" without showing whether that is a single set-based aggregate across every conversation the user belongs to, or a per-conversation lookup issued once per conversation inside one request handler.
`database.md`'s supporting index, `(channel_id, id DESC)` partial on `deleted_at IS NULL`, makes each individual per-channel count cheap, but a user who belongs to many channels (an active public-instance user, not just the brief's "handful of users" self-hosted case) still needs that confirmed as a single grouped query rather than N sequential index range-counts inside the sync-summary handler before the "sub-millisecond at this scale" resource target can be trusted at anything beyond the small self-hosted case.

## Open questions the specialist should have raised but did not

- How should the push-trigger decision account for iOS's actual backgrounding and suspension behavior instead of raw WS-connection presence, given the brief's own stated reason for the relay's existence (see finding 1).
- Should canvas rate limiting be split into a persisted-op class and an ephemeral relay-only class with materially different numeric limits, and does the 20KB/s steady-state traffic budget already set in `voice-canvas.md` set the real ceiling for the latter (see finding 2).
- Does the 64-bit snowflake reserve any bits for a node or shard identifier, and if not, what is the migration plan for the official instance if it ever runs more than one writer process (see finding 3).
- What concrete capability does the 90s in-memory resume-session record provide beyond what the stateless global catch-up cursor already provides on any reconnect (see finding 4).
- Is the WS ticket minted from an opaque server-side session token per `security.md`, or from a JWT as the borrowed echo phrasing implies, and if opaque, does the ticket-issuance flow still need updating to match (see finding 5).
