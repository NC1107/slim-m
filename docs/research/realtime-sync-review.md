# Realtime Sync and Messaging Protocol: Adversarial Review

Target document: `docs/research/realtime-sync.md`.
Cross-checked against `docs/BRIEF.md`, the owner decisions, the stack decision, and the sibling research reports in `docs/research/` (`voice-canvas.md`, `database.md`, `security.md`, `networking-relay.md`, `flutter-client.md`, `performance.md`, `reference-check-in-relay.md`).
The off-limits echo-messenger repository was not read and no finding below relies on it.
Where this review checks for a quietly reintroduced echo-messenger pattern, it does so only by testing whether the specialist report supplies its own first-principles rationale, not by comparing structure to the forbidden reference.

Severity key: critical findings would force a redesign of the decision as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The push-trigger "live connection" check misclassifies suspended iOS clients as reachable, and there is no fallback re-check

The push-trigger decision is a single-shot check performed at commit-and-fan-out time: if a recipient device shows a live WebSocket connection, no push is sent, full stop.
The gateway section sets heartbeat at roughly every 20 seconds with two missed heartbeats before the server treats a connection as dead.
That gives a window of on the order of 40 seconds, possibly longer depending on implementation, during which an iOS app that has been backgrounded and suspended by the OS still looks "live" in the server's connection table, because the TCP socket can sit open and unacknowledged for a while after the process itself stops running Dart code.
Concrete failure: user A backgrounds the app, user B sends a message twelve seconds later, the server sees user A's connection as live, no push fires, and because the push decision is made once at commit time with no later re-check, that specific message is never pushed at all.
User A only sees it on next foreground open or the next unrelated event that happens to trigger a reconnect.
This is not a rare edge case, it is the exact scenario the brief itself names as the reason the relay exists: "mobile applications cannot reliably receive incoming connections or maintain persistent connections while backgrounded."
`networking-relay.md` inherits the identical blind spot, since its wake-push kind is also gated on "the WebSocket is not already live," so the gap spans two sibling reports, not one.
Linux does not have this problem, a desktop socket is not suspended by the OS the way an iOS app is, so the design is well calibrated for the brief's secondary platform and miscalibrated for iOS, the brief's stated primary initial testing platform.
Fixing this needs either a client-reported foreground and backgrounded lifecycle signal that actively closes or marks the socket on backgrounding, or a second, short-timeout liveness check decoupled from the general-purpose heartbeat, or a delayed re-verification before a push decision is treated as final.
Any of those is a real change to the push-trigger decision, not a constant tweak.

### 2. The shared backpressure channel is never reconciled with Voice Canvas fan-out, and its "closing is always safe" claim does not hold under the canvas's own stated traffic budget

The backpressure decision bounds each connection's outbound channel by bytes, for example a 1 MB cap by the document's own example, and closes the connection on overflow rather than dropping or blocking.
The stated justification is that because resync is always correct, closing a slow connection is "a safe control valve, not a special case."
`realtime-sync.md` never states whether Voice Canvas traffic rides this same physical connection and outbound channel, and nothing in the client architecture (`flutter-client.md` describes one WebSocket socket per client, not several) suggests a separate one exists.
`voice-canvas.md` sets its own steady-state budget at under 20 KB per second per actively-drawing user, fanned out to every other connected participant.
Using both documents' own numbers: four people drawing at once in a call, fanned out to a fifth participant on a temporarily slow mobile link, is roughly 80 KB per second of legitimate canvas traffic alone arriving for that one recipient, filling a 1 MB channel in about twelve seconds.
At that point the stated policy closes the connection, during the app's own flagship feature, for a participant who did nothing wrong.
The "closing is always safe" claim is true for chat, where losing a connection just means a slightly stale reload, but it is not true for an in-progress collaborative canvas session, where a forced reconnect mid-drag is a visible, disruptive UX failure, not a harmless resync.
This needs a real fix in the backpressure decision itself, such as a traffic-class-aware channel (durable ordered events get the hard-close policy, ephemeral high-frequency events get coalesce-or-drop-newest instead), not a bigger constant.

### 3. Stateless resume prices out at zero, but a synchronized reconnect burst against dozens of scopes is not modeled anywhere and threatens the self-host lightweight target

The resume decision is justified as removing a class of state rather than adding one, with the only acknowledged cost being "slightly more payload on instant reconnects."
That framing understates the real cost.
The catch-up sync section describes the bundled sync call as running "per scope runs an indexed range scan," phrasing that reads as one query per scope in a loop rather than one grouped statement, and the document never confirms which.
For a user in dozens of channels, an ordinary reconnect blip, a phone moving between WiFi and cellular, a home router hiccup, now costs dozens of read-pool queries instead of a lightweight in-memory resume check.
The failure mode that matters is not one user reconnecting, it is many: a self-hosted friend-group server's WiFi access point reboots, every connected client's socket drops within the same few seconds, and every one of them reconnects and issues its own multi-scope catch-up burst against the single serialized-writer-adjacent SQLite read pool at the same moment, on exactly the "handful of users, extremely lightweight" box the whole stack was chosen to protect.
Nothing in `realtime-sync.md` or `performance.md` prices this reconnect-storm cost; `performance.md`'s per-event budget covers a single persisted write, not a synchronized N-scope read burst across many simultaneously reconnecting sessions.
This undercuts owner decision 7's rationale for the single-process, in-memory design ("simplest and lightest") precisely at the scale that decision was meant to serve.
The fix is a real one: either confirm and enforce a single grouped query across a user's scopes instead of N sequential ones, or add reconnect coalescing or per-connection resync debounce, or both; "the client already needs a durable local cursor anyway" does not by itself bound the burst this creates under correlated reconnects.

## Major findings

### 4. In-process rate-limit state has no eviction policy, and the connection-attempt bucket is keyed by an attacker-controlled value

The rate-limiting decision is in-process token buckets keyed by user and limit class, with a trait for a later shared-store swap.
Nothing in the document describes sweeping or evicting idle buckets.
The per-IP connection-attempt bucket is the sharp case: IP is attacker-controlled in the sense that a client can present many different source addresses over time (rotating mobile carrier NAT addresses, or a deliberate attacker), and every novel IP that hits the connect path plausibly allocates a new bucket entry that nothing here ever removes.
Over the "many years of unattended operation" horizon the stack decision explicitly designs for, this is a slow, unbounded memory growth path on exactly the long-running single process the official instance and every self-host both run.
The allowed check-in-relay reference already solved this exact problem, sweeping idle buckets on a ten-minute cutoff, and this document does not reconcile with or even mention that precedent, despite `networking-relay.md` drawing on the same reference elsewhere in this research pass.

### 5. The ticket-minting REST call is not clearly covered by any of the enumerated rate-limit classes

The gateway decision mints the WebSocket connection ticket "over an authenticated REST call," separate from the WebSocket upgrade itself.
The rate-limiting section enumerates connection attempts per IP, message sends per user per scope, typing events, and sync requests as the limited classes.
Ticket minting is not obviously any of these: it is not the WS upgrade (that is a separate step), it is not a message send, and it is authenticated, so an attacker only needs one valid session, not a fresh connection each time, to loop the mint endpoint.
If the per-IP connection-attempt bucket is only charged at actual WS upgrade, a client or a hijacked session can mint tickets in a tight loop with no stated budget at all.
This should be an explicit limit class, not an implicit assumption that it falls under an existing one.

### 6. Neither the message-send path nor the catch-up sync call states its transport, despite later sections assuming both are settled

`realtime-sync.md` states its own scope as the gateway lifecycle, ordering, catch-up sync, read state, typing and presence, rate limiting, and the push hook.
It never states whether a client sends a new message over an HTTP POST or as a WebSocket frame, yet the ordering section already assumes idempotent retries and an acknowledgment path exist, and the rate-limiting section already assumes a "typed error frame with a retry hint" exists as the rejection channel for a send.
Symmetrically, the catch-up sync section describes "one bundled sync call per reconnect" without stating REST or WebSocket-framed.
This matters concretely: if the sync call rides the same connection as finding 2's backpressure channel, a client badly behind across many channels could trip its own overflow cap while trying to resync, closing the very connection it needed to catch up on, an outcome that directly defeats the mechanism's own purpose.
Both transports should be stated explicitly rather than left to be inferred from adjacent sections that assume an answer already exists.

### 7. Presence visibility has no privacy toggle, an unflagged gap parallel to the one the specialist correctly caught for read receipts

Owner decision 5 defers visible read receipts specifically for privacy: "less presence fan-out, and simpler."
The presence decision in this same document broadcasts online and offline state to every user sharing a scope with the subject, on by default, with no mention of an opt-out or of it being a deferred, later-opt-in feature the way read receipts explicitly are.
Presence is a smaller information leak than read receipts, but it is the same category of leak (activity metadata visible to other users), and the document that got the read-receipts precedent right does not apply the same scrutiny to its sibling.
This is the same class of gap the specialist correctly caught elsewhere in this same report (see the cross-deployment DM flag), just not caught here; it deserves the same explicit "flag for a product decision" treatment rather than being decided implicitly by omission.

### 8. The backpressure byte cap does not state whether it is measured before or after permessage-deflate

The wire format is decided elsewhere to use permessage-deflate on the socket.
The backpressure decision sets a byte cap on the per-connection outbound channel but never states whether that cap counts pre-compression logical payload size, which is what actually occupies heap while queued, or post-compression wire bytes, which is what the network actually carries and is typically smaller.
An implementer who sizes the queue against wire bytes will under-provision real memory headroom relative to what is actually held resident while queued.
This is a small clarification, but it directly affects whether the finding 2 math holds in an implementation, since real queued bytes are the pre-compression figure.

### 9. A user's simultaneous devices share one rate-limit bucket per scope, so one device can starve another

The message-send limit is described as keyed by user and scope, not by user, device, and scope.
`database.md`'s schema is explicitly multi-device native, and the project's own multi-year horizon makes multiple concurrently active devices per user (phone plus laptop, or a future bridge or bot account) a real case, not a hypothetical.
A burst from one of a user's devices can consume the shared bucket and cause an unrelated, idle-until-now device belonging to the same person to get throttled for activity it did not generate.
This is a narrow case today but worth a deliberate choice (per-device sub-buckets under a shared ceiling, or an explicit accepted trade-off) rather than an implicit one.

## Minor findings

### 10. The catch-up sync per-scope and aggregate cap has no concrete number

The byte cap for backpressure gets an illustrative number, "for example a 1 MB cap."
The catch-up sync cap, described only as "capped per scope and in aggregate," gets none, even as an example, which makes it harder to reason about the finding 3 reconnect-storm cost or to size the snapshot-pointer fallback threshold the open questions already ask about.

### 11. The typing self-clear window is left vaguer than other tunable constants and is not listed among the specialist's own open questions

The document specifies the heartbeat interval, the backpressure byte cap example, and the ticket TTL as concrete numbers, and separately lists several of its own open questions about tuning those numbers.
The typing-indicator self-clear timeout is described only as "a short silence window" with no number at all, and unlike the other constants it is not included in the open-questions list, so it reads as decided when it is not.

### 12. The overflow-churn risk is flagged but has no monitoring mechanism this document or its self-host tier actually provides

The backpressure section's own risk note says a persistently slow client could churn reconnect cycles and that this is "worth monitoring close-code rate per connection."
Nothing in this document, and nothing in `performance.md`'s admin metrics section (which is scoped to a Prometheus endpoint and a built-in time-series store, not close-code-specific tracking), commits to actually surfacing this signal.
For a self-hosted admin with no dashboard tooling on day one, a persistently churning connection is invisible; "worth monitoring" names a good instinct without naming an owner or a mechanism.

### 13. Sequence-ordering discipline is sound, but nothing enforces it outside code review

The ordering decision correctly relies on there being exactly one writer per scope, and the stack decision separately notes the risk that any query ordering by identity instead of sequence would silently misorder and recommends a lint or automated check.
`realtime-sync.md` restates the ordering rule but does not itself carry that automated-check recommendation forward or assign it, so it is easy for this specific report's own guarantee to quietly depend on a check that lives only as an aspiration in a different document.

## On reintroduced echo-messenger patterns

Working only from whether each decision in `realtime-sync.md` carries its own first-principles rationale, since the reference itself is off-limits, no section reads as an unjustified copy.
Every decision states a concrete reason grounded in this project's own constraints (single writer per scope, single-process official instance, self-host lightness).
The one place a prior draft of this same document was previously found to have borrowed unreconciled phrasing from an outside pattern, the gateway ticket-auth flow, now states its own rationale (reverse-proxy URL logging) and no longer implies a JWT the way an earlier version of this document did; that specific concern appears to already be resolved and is not re-raised here.
The stronger residual risk in this pass is not a copied pattern, it is the opposite: finding 4 shows a place where the specialist did not reuse a good pattern already solved in the allowed check-in-relay reference (idle bucket eviction), which would have been the correct kind of reuse to make.

## Gaps the specialist should flag for an explicit decision

- Whether Voice Canvas traffic shares the chat gateway's physical connection, backpressure channel, and rate limiter, or gets its own, since finding 2 shows the current shared-channel assumption breaks under the canvas report's own stated traffic budget.
- Whether presence visibility needs the same explicit opt-in-later treatment owner decision 5 already gave read receipts, per finding 7.
- Whether the message-send path and the catch-up sync call are REST or WebSocket-framed, per finding 6, since the answer changes how findings 2 and 4 interact.
- Whether per-scope catch-up queries are batched into one statement or issued in a per-scope loop, per finding 3, since this decides how expensive a correlated reconnect burst actually is.
