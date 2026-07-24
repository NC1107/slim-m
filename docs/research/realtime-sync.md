# Realtime Sync and Messaging Protocol

This report designs the WebSocket gateway lifecycle, strict event ordering, offline catch-up sync, read state, typing and presence, rate limiting, and the push-notification trigger hook, on the already-decided stack: Rust and Axum on Tokio, SQLite in WAL mode behind a single serialized writer, UUIDv7 event identity paired with a server-assigned per-scope monotonic sequence, and schema-first JSON over HTTP and WebSocket.
A scope, as used here, is one independently ordered event stream: a text channel or a direct-message conversation, each backed by its own durable sequence counter.
Presence and typing are not scoped events and are addressed separately below.

## Gateway: connect, authenticate, heartbeat

Decision: the client mints a short-lived, single-use connection ticket over an authenticated REST call, then opens the WebSocket with that ticket, not its long-lived session credential.
Reverse proxies commonly log full request URLs, so a durable credential there widens the leak surface for no benefit; a 30-second TTL plus single-use redemption bounds it.
On redemption the server sends a `hello` frame with protocol version and heartbeat interval.
Heartbeat is an application-level ping and pong around every 20 seconds, not bare TCP keepalive, because mobile carrier NAT and many proxies silently drop idle connections inside typical keepalive timers.
Two missed heartbeats trigger reconnect with backoff and jitter.

## Resume is stateless, not session-based

Decision: the server keeps no per-connection resume state.
Every reconnect, after two seconds or two weeks offline, is handled by the same mechanism: a client-driven catch-up sync against a durably stored per-scope cursor.
Rejected: an in-memory session table keyed by a resume token, the more conventional approach, since it adds expiry races and a resume window a restart silently invalidates, for a benefit limited to sub-few-second reconnects that already replay almost nothing under the stateless path.
This follows directly from the per-scope sequence being durable and gap-free: the client already needs a durable local cursor for cold start and long-offline cases, so reusing it for every reconnect removes a class of state instead of adding one.

## Backpressure

Decision: each connection has a bounded outbound channel sized in bytes, not message count, for example a 1 MB cap, since message sizes vary widely.
On overflow the server closes that connection with a distinct close code rather than dropping frames.
This composes cleanly with stateless resume: because resync is always correct regardless of how far behind a client fell, closing a slow connection is an ordinary control valve, not a special case.
Rejected: unbounded queues, a memory risk from one wedged client, and blocking sends in the fan-out path, letting one slow socket stall every other client.
The fan-out loop sends non-blocking per subscriber channel, drained by a dedicated writer task per connection, so a slow writer only affects its own connection.

## Applying events strictly by total order

Decision: clients apply events ordered by scope and sequence, never by WebSocket arrival order, tracking a per-scope high-water sequence locally.
Because there is exactly one writer per scope, no vector clocks, Lamport timestamps, or merge logic are needed.
Optimistic local echo renders the client's own UUIDv7-identified event immediately, then reconciles it to the durable identity-and-sequence pair once acknowledged.
A unique constraint on scope plus client event id makes retries idempotent, so a resend after a dropped ack returns the original sequence, not a duplicate row.
Because sequence is contiguous per scope, a client seeing a jump greater than one in a scope it believes caught up knows unambiguously it missed something, for example a dropped frame during too brief a blip to trigger reconnect, and resyncs that scope immediately.

## Catch-up sync

Decision: one bundled sync call per reconnect, not one request per conversation.
The client sends its stored per-scope cursors for every scope it belongs to in a single request; the server validates membership, then per scope runs an indexed range scan on scope and sequence greater than the cursor, capped per scope and in aggregate, returning a continuation flag when truncated.
For a member of dozens of channels, one round trip instead of many is a direct win for the brief's network and battery goals, since each round trip is a radio wake on mobile.
The composite index the sequence counter already needs for uniqueness serves this query with no addition.
For a cursor so far behind that walking the full gap is wasteful, the server instead returns a snapshot pointer to the latest window, relying on ordinary scroll-back pagination for older history.

## Read state and unread counts

Decision: one row per user and scope storing a last-read sequence, updated only through a monotonic guard so a racing or stale update can never move it backward.
Unread count is computed on demand from an indexed range count, not maintained as a separately incremented counter.
A counter incremented on every fan-out multiplies write load against the single serialized writer path, the resource this architecture protects most, and can drift after a bug; a derived count from an already-indexed column is correct by construction and cheap here.
Read-state updates fan out only to the same user's other live connections, never to other users, matching the deferral of visible read receipts, keeping this channel smaller than messages themselves.

## Typing and presence

Decision: both stay fully ephemeral, never assigned a sequence, never persisted, and excluded from catch-up sync, since neither carries meaning after the fact.
Typing is client-debounced and server-relayed only to current members, with no explicit stop event; the client clears its own indicator after a short silence window, around 8 to 10 seconds, since an explicit stop event creates a stuck indicator whenever that one frame is lost.
Presence is derived, not stored: a pure function of whether the process holds a live connection for a user, computed from the same connection table fan-out already needs, broadcast only to users sharing a scope with the subject, so cost scales with a social graph, not server population.
A short grace period delays "went offline" announcements so an ordinary backgrounded reconnect never flickers a presence indicator.

## Rate limiting

Decision: in-process token buckets keyed by user and limit class, with no external dependency, matching the single-process architecture chosen for the official instance and required for a lightweight self-host default.
The limiter sits behind a trait so a shared-store implementation can be substituted at one seam if the official instance ever needs multiple processes, but only in-process ships for v1.
Separate budgets apply to connection attempts per IP, message sends per user per scope with burst plus sustained rates, typing events kept loose, and sync requests kept global since it is one bundled call.
On any breach the server returns a typed error frame with a retry hint rather than silently dropping it, since a dropped message is indistinguishable from data loss and local echo needs a definite accept-or-reject, not a guess.

## Push notification triggering

Decision: the trigger for a push is the same commit-and-fan-out step that delivers an event over the socket, not a separate path.
After an event's sequence is assigned and persisted, the server checks each scope member's device set; any device with a live connection is served and never generates a push, the majority case and the largest lever against redundant push volume and battery drain.
Devices with no live connection are queued after a short debounce window of a few seconds, so a burst of messages collapses into one wake, also protecting the relay's per-device send limits from an ordinary fast conversation.
Because a push is only a wake trigger and never a source of truth, a woken client runs the identical stateless catch-up sync described above, so push introduces no separate delivery path.

## Flag: direct messages assume a shared home server, and nothing says so

Owner decision 4 makes one backend deployment one community, and nothing in the brief or the decisions describes federation between deployments.
The scope model here, one durable sequence counter per conversation in a single writer's database, only works when both participants' accounts live in the same deployment.
That means Direct Messages, listed as core functionality, cannot work between users on different self-hosted servers, or between a self-hosted user and an official-instance user, under the current account model.
This deserves an explicit decision rather than discovery mid-build: either document DMs as same-deployment-only for v1, the option this report assumes, or scope federation as a deliberate future item.
