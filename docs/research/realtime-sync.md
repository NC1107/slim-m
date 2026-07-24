# Realtime Sync and Messaging Protocol

This report covers the WebSocket gateway, message identity and ordering, catch-up sync, read state, typing and presence, rate limiting, and how push notifications hook into the event flow.
It assumes the given stack: Rust/Axum, Postgres, Flutter/Riverpod, JSON-over-WebSocket with ticket-based auth, and an official push relay modeled on check-in-relay.
The single biggest lesson from echo-messenger is that its Voice Canvas shipped with no server-assigned ordering, which produced real, user-visible divergence bugs.
Every decision below treats ordering as a day-one architectural concern, not a follow-up.

## Wire format: JSON confirmed, not protobuf or msgpack

JSON-over-WebSocket is already the given stack decision, and it is the right one.
A single JSON envelope (`op`, `t`, `d`, plus a sequence field for resume) keeps one schema shape in both Rust and Dart with no codegen step.
Rejected: protobuf, whose build-toolchain and schema-sync burden is not worth it for a small team, and whose bandwidth win is irrelevant since voice and video never touch this channel (LiveKit's SFU carries that separately).
Rejected: msgpack, which saves bytes over JSON but loses human debuggability for a marginal win.
Binary sub-payloads, such as E2E ciphertext, stay base64-wrapped strings inside the envelope, matching echo's proven pattern, so every frame is text and the client never demuxes frame types.
Risk: JSON decode cost could matter on a very large public instance; that is a profile-and-revisit case, not a day-one concern.

## WebSocket gateway lifecycle

Connect: REST login issues a 30-second single-use WS ticket, client connects with `?ticket=`, JWT never touches the URL.
This is proven in echo-messenger and should be kept unchanged.
Server sends `hello` with a 30s heartbeat interval on connect; client reconnects if it sees no traffic for 60s.
Resume: the hub keeps a short-lived (90s) in-memory session record per connection (`session_id`, `last_sent_id`) after disconnect.
A client reconnecting inside that window replays only the gap via the same mechanism used for cold-start catch-up, instead of re-sending full state, which matters for battery and network use since a backgrounded phone reconnects constantly.
Backpressure: each connection has a bounded channel (256 messages).
A slow consumer's channel filling closes that connection rather than blocking the fanout loop, so one stalled client never affects any other connected user.
Rejected: unbounded per-connection queues (unbounded memory risk from one wedged client) and blocking sends in the fanout path (head-of-line blocking, a real denial-of-service risk).

## Message identity and ordering: snowflake, not ULID

Verdict: server-generated 64-bit snowflake IDs (timestamp plus in-process counter), used as the identity and ordering key for every persisted event in the system, not just messages.
Each server process is the sole writer for its own database, so no worker/datacenter coordination bits are needed, only a monotonic-clock guard against backward time jumps.
Rejected: ULID, whose strengths (client-side generation, coordination-free uniqueness) matter for multi-writer or offline-first systems; here the server is the single ordering authority by design, so client-generated authoritative IDs would reintroduce the ambiguity that caused echo's canvas divergence bugs.
Optimistic local echo still works with an opaque local UUID placeholder reconciled to the real ID on ack, so ULID's offline-compose benefit is not actually lost.
The key move: apply this same server-assigned ID scheme to Voice Canvas ops (strokes, image moves, clears), not just chat messages.
This is the direct fix for echo's documented gap, "no sequence numbers, vector clocks, OT, or CRDT," and it also applies echo's per-object-row lesson, since each canvas op becomes its own row keyed by this ID instead of an entry in a flat capped JSON array.
Risk: a 64-bit ID exposes approximate creation time, a pre-existing property of timestamp-ordered IDs generally, including ULID, and not a new leak.

## Catch-up sync after offline periods

Because every event shares one global monotonic ID space, catch-up is a single cursor: `GET /api/sync?after=<last_id>&kinds=message,reaction,canvas_op&limit=500`, returning one chronologically ordered page across every conversation the user belongs to.
This replaces a per-conversation fan-out of REST calls on reconnect, which matters directly for mobile battery and network use.
A `kinds` filter lets a client skip canvas backlog for channels it is not currently viewing.
Long gaps (weeks offline) are capped at page size and paginated with `has_more`, falling back to lazy per-conversation history loading instead of eagerly downloading everything, the same pattern Discord and Slack use.
Resource target: a typical daily reconnect gap should resolve as one indexed range scan returning well under 100 rows, sub-millisecond at this scale.

## Read state and unread counts

Store one column per (user, conversation): `last_read_message_id`, updated with `GREATEST(existing, new)` so it can never move backward from a stale or racing update.
Unread count is derived on demand, `COUNT(*) WHERE conversation_id = X AND message_id > last_read_message_id`, computed once inside the sync-summary query, not as a separately mutated counter.
Rejected: a materialized counter incremented on every send, which adds write amplification to every fan-out and can drift from the source of truth.
After initial sync, the client increments its local count as new messages stream over WS and resets it locally on read, so the server is only queried again on full resync.
Read-state updates fan out to the user's other devices; per-conversation read receipts visible to other users are a product opt-in, not a protocol requirement.

## Typing and presence

Both stay fully ephemeral, never persisted, matching what echo already got right for canvas avatar and stroke-preview events.
Typing: client-debounced, server-relayed only to conversation members, auto-expired client-side after 8-10s of silence instead of relying on an explicit stop event, avoiding the flap-prone start/stop desync class seen in canvas authority handoff.
Presence: derived directly from live WS connections in the hub, broadcast only to users sharing a conversation, with a short grace period before announcing "offline" so background/foreground bounces within the resume window never surface as a flicker.
Server-side rate limiting applies regardless of client throttling, since client cooperation cannot be assumed.

## Rate limiting

In-memory, per-process token buckets, matching check-in-relay's own proven approach for a single-instance deployment; this is the right call for the brief's "handful of users, extremely lightweight" default and should not force a Redis dependency onto self-hosters.
The limiter should be an injectable interface so the official hosted instance can swap in a shared-store implementation only if and when it scales past one process.
Starting limits: 10 WS connects/min/IP, roughly 1 message/s sustained per user with burst headroom, 1 typing event/3s per conversation, 20 canvas ops/s per user per channel (canvas is expected to be chattier), 30 sync requests/min per user.
Exceeding a limit returns a typed error frame with `retry_after_ms` rather than a silent drop; silently dropping ordinary messages is an undetectable correctness bug, unlike canvas's deliberate silent-drop for stale non-authority writes, which is a narrower, intentional case.

## Push notification triggering

The self-hosted server owns all device and mute-state knowledge; the relay stays a dumb, scoped forwarder, exactly as check-in-relay is designed.
After an event is committed and fanned out over WS, the server checks each recipient device for a live connection; if one exists, no push is sent, the biggest single win against redundant battery drain.
Only devices with no live connection outside the resume grace window get a push, via the relay, using its proven scoped-key model (one revocable, hashed key per self-hosted server).
Push payloads never carry message content for E2E-encrypted conversations, since the server never has plaintext to send; the client wakes, reconnects directly to the self-hosted server, decrypts, and posts its own local notification, the same two-phase pattern Signal uses.
For plaintext conversations only, a short preview can ride in the push payload itself.
Bursts of messages while backgrounded are debounced per device (3-5s window) into one wake or summary push rather than one push per message.

## Resource targets

An idle self-hosted gateway process (handful of users) should stay well under 50MB RSS.
Each connected WS client should add well under 100KB of server-side state (bounded channel plus a small struct), so 100 concurrent connections cost low single-digit MB total.

## Flag: the brief should state multi-device support explicitly

The brief's push-relay section refers to "the user's mobile devices" in the plural, implying multi-device support, but no section in Features or Account Model states it as a requirement.
Every decision above (WS resume per session, per-device push tokens, cross-device read-state fan-out) assumes multi-device-per-user from day one, because echo-messenger shows what happens when it is retrofitted late: refresh tokens never got bound per device, so "log out all other devices" only affects sessions currently connected.
Recommend adding an explicit multi-device requirement to the strategy doc.
