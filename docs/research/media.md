# Real-Time Media: Voice, Screen Share, and Voice Canvas Integration

Status: draft specialist report, feeds into STRATEGY.md.
Scope: voice calls, screen sharing, and how both surface as movable Voice Canvas objects.
Companion reading: `docs/BRIEF.md` and the echo-messenger reference notes.

## Decision: LiveKit as the self-hosted SFU

slim-m should use LiveKit (self-hosted, Apache 2.0, Go server, official Docker image) as its selective forwarding unit for voice, video, and screen share.
This is the same choice echo-messenger made, and its notes confirm the integration pattern works in production: server-minted short-lived JWTs scoped to a server-derived room id, a Riverpod wrapper with disposal guards, active-speaker events, and RTC stats.
Reuse that pattern.

Alternatives considered and rejected:

- **Custom Pion-based SFU** (hand-rolled or ion-sfu style). Owning congestion control, simulcast, bandwidth estimation, and ICE/TURN fallback from scratch, with no equivalent to LiveKit's Flutter SDK, means maintaining a WebRTC media engine instead of a messaging app; ion-sfu's pace has also slowed considerably.
- **mediasoup**. A capable media engine, but a library, not a server; slim-m would still build room management, signaling, and token auth in Node, a second runtime and language against "avoid a sprawl of moving parts."
- **Janus Gateway**. Mature and flexible, but its plugin-based room model and admin surface are far more DIY than LiveKit's, and Flutter support is community-maintained, not official.
- **Jitsi (JVB + Jicofo + Prosody)**. Three coordinated services plus XMPP is too many moving parts for a "handful of users" self-host target.
- **Raw peer-to-peer WebRTC mesh**. Degrades past a few participants as bandwidth and CPU scale with participant count; echo already moved away from this, and Voice Canvas group calls need an SFU from day one.

## Deployment weight and self-host resource targets

Run LiveKit as a single container, single node, for the default self-host profile.
Redis is only required for multi-node deployments; a single-node self-host does not need it, keeping the stack at "Postgres plus one Rust binary plus one LiveKit binary," no extra database to operate.
Use LiveKit's built-in TURN server (TURN/TLS muxed on 443) instead of deploying coturn separately, removing a service from the self-host checklist and giving working TURN behind ordinary NAT without extra DNS or certificate setup, since it can share the reverse proxy's certificate.
Fall back to an external STUN/TURN provider only as a documented escape hatch for double-NAT or CGNAT hosts.

Target resource budget for a "handful of users" self-host (up to roughly 10 concurrent voice/video participants), pending validation by a real load test: idle node under 50 MB RSS, near-zero CPU; voice-only room under 150 MB RSS; a video room with capped-resolution bubbles and simulcast under 500 MB RSS and one to two vCPUs, since an SFU forwards packets rather than transcoding.
Screen share is just another, usually higher-resolution, track, so budget it like one extra camera stream, not a separate cost category.

## Codecs and simulcast

Launch codec set: Opus for audio, VP8 with simulcast for video, the most universally supported simulcast codec across iOS, Android, and Linux libwebrtc, which matters since Linux is a primary platform, not an afterthought, per the brief.
Defer H.264 hardware-encode as an iOS-only battery optimization until telemetry shows it is needed; a second negotiated codec is complexity earned with data, not assumed up front.
Skip AV1/VP9 SVC for v1: hardware decode support is not yet consistent across the target devices, and simulcast already solves adaptive quality per subscriber; revisit once decode support is broadly hardware-accelerated.

Tie LiveKit's simulcast subscription features directly to the Voice Canvas viewport: adaptiveStream so a bubble rendered small on a zoomed-out canvas subscribes to a low layer, dynacast so the server stops encoding layers nobody subscribes to.
Go further than LiveKit's built-in behavior: when a bubble or screen share sits fully outside a client's visible viewport on an infinite canvas, unsubscribe entirely rather than merely downgrading, since an infinite canvas can accumulate far more streams than any one viewport shows, and paint-level culling must extend to media subscriptions or cost scales with total participants rather than visible ones.

## Mobile CPU and battery

Cap camera capture resolution for bubbles at roughly 640x480 to 960x540, since bubbles are rarely rendered larger than a few hundred pixels and capturing 1080p wastes CPU and battery.
Enable Opus DTX so idle microphones stop consuming encode CPU and bandwidth during silence, helping both battery and self-host bandwidth cost with several open channels.
Rely on adaptiveStream's automatic pause of off-screen tracks, and defer client-side video effects such as background blur past v1, since they cost CPU and battery for a feature not in the brief.

## Screen sharing

On iOS, system-wide screen share requires a ReplayKit broadcast extension, capped at roughly 50 MB of memory, a real constraint on frame buffering to load-test early rather than discover late.
On Linux, screen capture goes through PipeWire via xdg-desktop-portal on X11 and Wayland; flutter_webrtc's Linux desktop support, covering capture, hardware decode, and stability, is less mature than iOS, Android, or Web, and the brief lists Fedora as a primary testing environment alongside iOS.
Recommend an early spike, before deeper Voice Canvas work, validating LiveKit plus flutter_webrtc on Fedora (capture, PipeWire share, decode performance) as insurance against a Linux-specific gap surfacing after the architecture is locked in.

## Camera bubbles and screen shares as Voice Canvas objects

Keep the media plane and the canvas plane strictly separate.
LiveKit owns the audio/video RTP streams and never carries canvas state; the canvas server owns only the position, size, and z-order of each bubble or screen-share frame as a canvas object, referencing the LiveKit participant or track identity as a stable pointer, never embedding media.
A client renders a bubble by painting the matching LiveKit video track inside its canvas object's transform; video pixels never touch the canvas data model.

Store bubble and screen-share position and size in world coordinates, the same absolute space strokes live in, not viewport-relative or device-pixel coordinates.
This corrects a real echo-messenger bug, where screen-share windows originally used the sender's raw CSS-pixel position, snapping to the wrong place on a differently sized receiver viewport, fixed after the fact with a normalization scheme and a legacy migration shim.
slim-m's brief wants bubbles and screen shares to be movable, resizable, AR-glasses-style objects arranged in shared space, making them world content by definition, so deciding that on day one avoids repeating echo's migration.
The exception is UI chrome, such as toolbars and cursor labels, which must stay viewport-relative and clearly separate from canvas objects.

Follow the per-object model the canvas domain should adopt: a `canvas_objects` row per bubble or screen-share frame with id, type, z, transform, and a track reference, not a flat capped JSON array, reusing echo's lesson that flat JSON blobs cannot support move, resize, or z-order.

## Tokens and security

Mint short-lived LiveKit JWTs (a few minutes, matching echo's 5-minute pattern) server-side, scoped to a server-derived room id, never client-supplied, so a client cannot escalate into a room it is not a member of.
Unlike echo, scope the grant by role from the start (publisher for members, subscribe-only for listener roles) rather than a uniform full-publish grant fixed later.
Nonce participant identities on rejoin to avoid SFU identity collisions within the participant-idle window, matching echo's fix for a real `setMicrophoneEnabled` timeout bug.

## Interface with the push relay

Incoming voice calls need to wake a backgrounded or force-quit mobile client reliably, unlike a normal message notification.
On iOS this means PushKit VoIP push paired with CallKit, not a regular APNs push; PushKit wakes the app even when force-quit and is the only App Store-compliant way to trigger a CallKit incoming-call screen.
The push relay's data model should account for a separate VoIP push token per device and a distinct "incoming call" event type, a cross-cutting requirement to confirm with whoever owns the relay design, since it changes the relay's token schema.

## Open questions

- Whether PushKit VoIP token registration is in scope for the push relay's first version or deferred, since it changes the relay's data model.
- What concurrent-participant threshold should trigger multi-node LiveKit plus Redis on the official hosted instance; this needs a load test, not a guess.
- Whether the canvas domain's per-object table lands before or alongside media integration, since bubble and screen-share position sync depends on it existing.
- Whether an early Fedora flutter_webrtc validation spike is already planned in the roadmap, given it is flagged here as a real risk.
