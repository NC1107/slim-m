# Real-Time Media Plan: Adversarial Review

Target document: `docs/research/media.md`.
Cross-checked against `docs/BRIEF.md`, the sibling reports in `docs/research/` (`voice-canvas.md`, `voice-canvas-review.md`, `security.md`, `database.md`, `realtime-sync.md`, `backend.md`, `devops.md`, `networking-relay.md`, `appstore.md`, `performance.md`, `oss.md`), and the echo-messenger and check-in-relay reference notes.

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The plan's own persistence model for camera bubbles and screen shares contradicts `voice-canvas.md`, the sibling report that actually owns the canvas schema

`media.md`'s "Canvas object model reuse" recommendation says plainly: "Model camera bubbles and screen shares as rows in the same per-object `canvas_objects` table (id, type, z, transform, track reference) the canvas domain should adopt, not a flat capped JSON array."
`voice-canvas.md`, written to own exactly this schema, says the opposite in its "Object model" section: "Two object families exist.
Content objects (stroke, image, gif, window) are persisted, versioned, and undoable.
Presence objects (camera bubble, screen-share tile) are ephemeral, never written to this table... their position updates go over a pure ephemeral broadcast channel that never touches the op log."
This is not a nuance, it is a direct contradiction about whether the entities `media.md` is responsible for get a durable row at all.
The two designs have materially different consequences: a persisted row means bubble and screen-share position history becomes part of `voice-canvas.md`'s own moderation audit trail ("who drew what, when") and inherits its retention and undo semantics, while an ephemeral broadcast means bubbles reset on rejoin, matching echo-messenger's own proven pattern and avoiding indefinite storage of a participant's video-window movement.
`database.md`'s already-committed schema, `canvas_objects(id, channel_id, kind, z_index, transform, props, from_user_id, created_at, updated_at, deleted_at)`, has no `track_reference` column either, so even taking `media.md`'s recommendation at face value, the concrete schema it would need to land in has not been updated to hold it.
This needs resolution before implementation starts, not during it: either `media.md` is wrong and bubbles stay ephemeral as `voice-canvas.md` designed, or `voice-canvas.md`'s object model needs to change to support a persisted, privacy-reviewed presence object, which is a materially different feature with different retention and disclosure obligations.

### 2. TURN/TLS muxed on port 443 conflicts with the reverse proxy the rest of the stack already puts on port 443, and the plan never resolves the collision

`media.md` recommends "LiveKit's built-in TURN server (TURN/TLS muxed on 443) instead of deploying coturn separately... since it can share the reverse proxy's certificate."
Sharing a certificate is not the same as sharing a listening port.
`security.md` and `devops.md` both already commit the self-host default to a Caddy reverse proxy terminating TLS on port 443 for the main API and web traffic ("self-hosters get automatic TLS via the check-in-relay Caddy pattern," "Compose example: server, postgres... and Caddy for automatic TLS").
LiveKit's TURN/TLS mux needs to see the raw TCP/TLS bytes on 443 to distinguish TURN traffic from ordinary HTTPS, which an HTTP-level reverse proxy vhost or `Host()` routing rule cannot do, since that kind of routing only applies after a normal HTTPS request is already parsed, not to a differently-shaped TLS session carrying TURN framing.
In practice this forces one of: a dedicated second public IP for LiveKit, TCP-level SNI-passthrough routing configured in the shared proxy (real added complexity Caddy and Traefik both support but neither devops.md nor media.md configures), or dropping the "no coturn, port 443 only" claim and running TURN/TLS on a separate port with a documented firewall exception.
None of these is free, and none is mentioned anywhere in the plan or in the compose topology `devops.md` already wrote.
As written, the self-host deployment story in `media.md` and the self-host deployment story in `devops.md` describe two different, incompatible port-443 owners on the same box, and the plan's only acknowledgment is a generic "pending validation," not an actual resolution path.

## Major findings

### 3. The relay schema change `media.md` asks for contradicts the relay's own already-written design, and the real gap sits in a different table nobody has updated

`media.md`'s "Interface with the push relay" section asks that "the push relay's data model should account for a separate VoIP push token per device and a distinct 'incoming call' event type... since it changes the relay's token schema," and repeats this as an open question ("confirm with whoever owns the relay design").
`networking-relay.md`, the sibling report that owns that design, already explicitly rejected exactly this: "A persistent devices table, per-user, per-device rows, turns a stateless forwarder into a second copy of the home server's device registry and buys nothing... the relay stays a dumb forwarder with no devices endpoint at all."
In that design the relay never stores tokens of any kind; the home server passes whatever token it wants notified at send time via `platform`/`kind`/`token` fields, and `networking-relay.md` already routes `kind=call` through a separate APNs VoIP topic and push type.
The open question `media.md` raises has therefore already been answered elsewhere in the same research pass, just not the way `media.md` assumed, which means the "confirm with whoever owns the relay design" ask is stale rather than open.
The real, still-unaddressed gap is one level down: `database.md`'s already-committed `devices` table has exactly one `push_token_ref` column per device row, and an iOS device genuinely needs two independent, independently-rotating tokens, a regular APNs/FCM token for message push and a separate PushKit VoIP token for incoming-call push.
Neither `media.md` nor `database.md` catches that the current schema cannot hold both.
This is the actual required adjustment, and it belongs in the home server's `devices` table, not the relay.

### 4. No mid-call token refresh path for a short-lived LiveKit JWT on flaky mobile networks

`media.md` adopts "a few minutes, matching echo's 5-minute pattern" for LiveKit JWT lifetime, explicitly to bound the exposure window of a kicked member's still-valid token, per echo's own reference notes.
The plan never addresses what happens when a signaling reconnect (a WebSocket drop from a WiFi-to-cellular handoff, app backgrounding, or an elevator dead zone, all common on mobile) occurs after the token has expired but the call, from every other participant's perspective, is still ongoing.
A reconnect that requires a still-valid token to succeed will silently drop that participant from an otherwise-live call, unless the client is explicitly designed to mint and hand off a fresh token before or during reconnect.
`media.md` never mentions a token-refresh callback, a pre-expiry re-mint, or any mechanism at all for keeping a multi-minute call alive past the token's own multi-minute lifetime, which is a real tension between the stated security goal (short-lived tokens) and the stated platform reality (Linux and iOS are both explicitly primary, and mobile networks flap).

### 5. Kicked or banned participants are not forcibly evicted from a live call, only prevented from rejoining once their token expires

`media.md` reuses echo's mitigation without naming its own limitation: a short TTL "bounds the exposure window," it does not close it.
Echo's own reference notes are explicit that this gap exists because "the server has no LiveKit management-API client wired to force-evict a participant," and that issue is unresolved in the source material `media.md` is drawing from.
`security.md` lists kick and ban as first-class moderation permissions and names "an abusive or privilege-escalating user" as an in-scope adversary, and the brief asks for "excellent... moderation tools."
`media.md` never mentions LiveKit's room-service API for forcibly removing a participant on ban or kick, so as written, a banned user's live audio, video, or screen share continues publishing to the room for up to the full token lifetime after the ban is issued, carrying forward a known, named limitation from the reference material without flagging it as one.

### 6. No network egress bandwidth budget anywhere, for the resource dimension an SFU actually spends the most on

`media.md` carefully budgets idle RSS, per-room RSS, and vCPU count for the self-host profile, but never states a bandwidth number.
An SFU's dominant cost is egress fan-out, roughly proportional to the number of publishers times the number of subscribers each publisher's selected simulcast layer reaches, not CPU.
`devops.md` explicitly targets arm64 and Raspberry Pi-class self-hosting for the official images, exactly the deployment profile most likely to be bandwidth-constrained on a residential upstream connection rather than CPU-constrained.
A "handful of users" video room with several bubbles active can plausibly produce tens of megabits of aggregate egress, enough to saturate a typical home uplink, and the plan gives the self-hoster no number to plan against, size their connection for, or alert on.

### 7. Screen share is costed as "just another camera stream" while camera streams get an explicit resolution cap and screen shares get none

`media.md` caps camera bubble capture at "roughly 640x480 to 960x540" for CPU and battery reasons, then separately states screen share should be "budget[ed]... like one extra camera stream, not a separate cost category."
Screen content, unlike a small floating face bubble, typically needs materially higher resolution and bitrate to stay legible, since the brief's own screen-share use case (following someone's shared work) fails if text is unreadable.
No resolution or bitrate ceiling is ever set for screen share, so the "one extra camera stream" cost model is inconsistent with the plan's own logic for why camera bubbles needed a cap in the first place, and the brief's Voice Canvas explicitly allows multiple simultaneous floating screen shares as movable objects, which multiplies whatever the real, uncapped cost turns out to be.

### 8. Decode-side CPU and battery cost of VP8 on iOS and Linux is never analyzed, only encode-side cost

`media.md` discusses H.264 hardware encode only as a future iOS battery optimization for a device's own outgoing camera, deferred "until telemetry shows it is needed."
It never addresses the decode side: a client in a Voice Canvas session with several visible camera bubbles is decoding several concurrent incoming VP8 simulcast streams at once, which is exactly the "arrange every camera in space" scenario the brief names as a defining feature.
iOS libwebrtc has no hardware VP8 decode path; VP8 decode there runs in software (libvpx), competing directly with the canvas's own render budget (`voice-canvas.md`'s 60fps target) for CPU and battery on the same device.
The plan's codec section treats VP8 as a settled, low-risk default because it is "the most universally supported simulcast codec," without ever measuring or even naming the decode-side cost of the multi-stream case the app's own headline feature creates.

### 9. Group-call SFU privacy is a residual risk `security.md` names explicitly, and `media.md`, the report about that exact SFU, never surfaces it

`security.md`'s verdict states plainly: "group calls route through a server SFU where the operator can access media, with SFrame E2EE as a later option," listed as a residual risk alongside "1:1 calls stay peer-to-peer, effectively end-to-end."
Group voice and group screen share, not 1:1 calls, are the primary described use case in the brief (Group Chats: voice calls, screen sharing) and the substrate the Voice Canvas is built on.
`media.md` is the report that designs that exact SFU in detail, including token scoping, room derivation, and identity nonce handling, all real security care, but never once repeats or even references the one sentence its own sibling security report already wrote about what a self-hosted operator can see.
A specialist report this careful about token exposure windows should not be silent on the fact that the media it forwards is visible in the clear to whoever runs the box, especially given the brief's own ambiguous "lightweight encryption appropriate for a messaging application" framing that `security.md` had to resolve explicitly.

### 10. Full unsubscribe at the viewport boundary has no debounce, hysteresis, or keyframe-cost discussion

`media.md` goes "further than LiveKit's built-in behavior" by fully unsubscribing bubbles and screen shares outside the visible viewport rather than merely downgrading their layer.
A full unsubscribe followed by a resubscribe requires the SFU to deliver a fresh keyframe before video resumes, which on typical self-hosted latencies produces a visible freeze or black flash.
An infinite canvas invites continuous panning and zooming near a bubble's edge, which without an explicit hysteresis margin or debounce window around the viewport boundary will toggle a straddling bubble's subscription state repeatedly, producing exactly that freeze-and-recover flicker on every toggle.
The plan states the policy (unsubscribe fully, not just downgrade) without addressing the interaction cost that policy introduces on the exact input surface, continuous pan and zoom, the canvas is built around.

## Minor findings

### 11. Mediasoup's rejection reasoning is inconsistent with a decision the rest of the project already made

`media.md` rejects mediasoup partly because it "would still build room management, signaling, and token auth in Node, a second runtime and language against 'avoid a sprawl of moving parts.'"
`backend.md` and `oss.md` already accept a two-language split for the relay (Go) versus the main server (Rust) as the right tool for two different problems, not a sprawl to avoid.
LiveKit remains the stronger choice for other reasons already in the report (official Flutter SDK, managed room model), so this does not change the recommendation, but the stated rationale borrows a "one fewer language" argument the project has already decided not to apply elsewhere.

### 12. The "SFU forwards packets rather than transcoding" framing understates real per-participant CPU work

Simulcast layer selection, RTCP handling, keyframe request brokering, and active-speaker level detection are all real per-participant CPU work an SFU performs, not pure packet forwarding.
The plan already flags its resource numbers as "pending validation by a real load test," which is the right caveat, but the "forwards packets rather than transcoding" phrasing reads as more reassuring than the actual workload, and a load test should specifically include a multi-bubble video room rather than only a voice-only baseline.

## Gaps: important questions the specialist never addressed

- Which persistence model actually governs camera bubbles and screen shares, given the direct contradiction with `voice-canvas.md` (see finding 1).
- How TURN/TLS-on-443 muxing coexists with the reverse proxy that `devops.md` and `security.md` already put on port 443 for the main API in the same self-host compose stack (see finding 2).
- What actually needs to change, and where, to carry a second per-device token type (VoIP versus regular push), now that the relay's own design rejects the schema change `media.md` asked it to make (see finding 3).
- How an in-progress call survives a signaling reconnect after its LiveKit token has already expired (see finding 4).
- How a kicked or banned participant is removed from a live call immediately, not merely blocked from rejoining later (see finding 5).
- What bandwidth budget the self-host default profile should target, given arm64 and residential-upload deployment is an explicit target elsewhere in the research (see finding 6).
- What resolution or bitrate ceiling applies to screen share, given camera bubbles got one and screen shares did not (see finding 7).
- What the decode-side CPU and battery cost of several concurrent VP8 streams looks like on iOS and Linux, not just the encode-side cost of one outgoing camera (see finding 8).
- Whether the plan should explicitly disclose, the way `security.md` already does, that a self-hosted operator can access group call media in the clear (see finding 9).
