# Real-Time Media: Voice, Video, and Screen Share

Status: specialist report, feeds into STRATEGY.md.
Scope: voice calls, video, and screen sharing, and how bubbles and screen shares surface as Voice Canvas objects.

## Decision: self-hosted LiveKit as the SFU

slim-m runs voice, video, and screen share through a self-hosted LiveKit SFU (Apache 2.0, Go server, official Docker image), kept as a media plane strictly separate from the chat and canvas control plane.
The choice rests on four independent merits.
LiveKit ships an official Flutter SDK across iOS, Android, and Linux, matching slim-m's three client platforms with one supported integration rather than a patchwork of community bindings.
It packages as a single self-hostable container, fitting a "handful of active users" target where added services are weight the brief wants avoided.
It includes a built-in TURN server, so a self-hoster gets working NAT traversal without standing up a separate coturn deployment.
And it supports VP8 simulcast, the most universally supported simulcast codec across iOS, Android, and Linux libwebrtc, which matters since a server without its own media engine needs a codec path that works everywhere.
Flutter coverage, one container, built-in TURN, and broad simulcast support together settle LiveKit as the SFU, independent of any other project's prior use of it.

## Alternatives considered and rejected

A hand-rolled or Pion-based SFU means owning congestion control, simulcast, bandwidth estimation, and ICE and TURN fallback from scratch, with no equivalent Flutter SDK, turning a messaging app into a WebRTC media engine project.
Mediasoup is a capable media library but not a server; slim-m would still build room management, signaling, and token auth in a second runtime, against the brief's instruction to avoid a sprawl of moving parts.
Janus Gateway is mature but far more do-it-yourself with only community Flutter support, and Jitsi's JVB, Jicofo, and Prosody stack is three coordinated services plus XMPP, too many moving parts for a lightweight self-host target.
Raw peer-to-peer mesh degrades as bandwidth and CPU scale with participant count, and Voice Canvas group calls need an SFU from the first multi-person session, not as a later fix.

## Deployment and the port 443 resolution

LiveKit runs as a single node with no Redis in the default self-host profile, since Redis is only a multi-node coordination requirement; the stack stays at one Rust binary plus one LiveKit binary, no extra database process to operate.
LiveKit's TURN and media path need an explicit UDP port range, or host networking, separate from the plain TCP the app server uses; misconfigured SFU networking behind Docker is the most common self-host failure mode for WebRTC, so the compose documents it.
Both LiveKit and the app's reverse proxy want port 443, resolved explicitly: Caddy owns 443 for the REST and WebSocket API, and LiveKit's TURN and TLS listener runs on its own documented port with its own UDP media range, so the two never fight over one socket.
SNI passthrough or a second IP is documented as an advanced option for operators who want LiveKit's TURN muxed onto 443 too, but the compose file never claims a 443-only deployment as the default.

## Codecs

Launch codecs are Opus for audio and VP8 with simulcast for video, and nothing else ships in v1.
H.264 hardware encode is deferred as a possible iOS-only battery optimization until telemetry shows it is needed, since a second codec is complexity earned with data.
AV1 and VP9 SVC are skipped for v1 because hardware decode support is not yet consistent across the target devices, and simulcast already solves adaptive per-subscriber quality without them.

## Capability tokens and call lifecycle

LiveKit room access uses short-TTL capability tokens, minted server-side at join time and scoped to the joining member's permission bitmask, publisher grants for members, subscribe-only for listener roles, never supplied or trusted from the client.
The room id is server-derived from the channel or DM, so a token cannot be redirected into a room its holder is not a member of.
A kick or ban does not merely stop future token minting: it calls LiveKit's room-service API to evict the participant immediately, so media stops flowing within the same action that removes membership.
Because the TTL is short by design, a mid-call reconnect needs its own path: the server re-mints and hands off a fresh token before the old one lapses, so a brief blip does not silently drop a participant's media mid-call.

## Capture caps and iOS decode cost

Camera capture for canvas bubbles is capped at roughly 640x480 to 960x540 with an explicit bitrate ceiling, since bubbles are rarely rendered larger than a few hundred pixels and full sensor resolution wastes battery for pixels nobody sees.
Screen share gets its own resolution and bitrate ceiling rather than being costed as just another camera stream, since screen content is usually higher resolution and text-dense, and an uncapped share can dominate egress bandwidth alone.
Opus DTX is enabled so an idle microphone stops consuming encode CPU and bandwidth during silence, helping both battery life and self-hosted bandwidth cost with several channels open.
iOS has no hardware VP8 decode, so decoding several concurrent streams is measured against the Voice Canvas render budget rather than assumed free, a real risk validated by an early device measurement since a canvas full of bubbles is where decode and paint cost compete for the same frame budget.

## Camera bubbles and screen shares as Voice Canvas objects

The media plane and the canvas plane stay strictly separate.
LiveKit owns the audio and video RTP streams and never carries canvas state, while the canvas server owns only the position, size, and z-order of each tile as a canvas object, referencing the LiveKit participant or track identity as a stable pointer, never embedding media itself.
A client renders a tile by painting the matching LiveKit video track inside its transform, so video pixels never touch the canvas data model.
Bubble and screen-share position and size are stored in absolute world coordinates, the same space strokes and pasted images live in, never viewport-relative or device-pixel coordinates.
This is the one point in the media plan informed by echo-messenger's canvas work: an earlier version of that project's screen-share windows used the sender's raw device-pixel position, snapping to the wrong place on a receiver with a differently sized viewport, fixed only after the fact with a coordinate-normalization pass.
Committing to world coordinates from day one avoids repeating that bug and matches the brief's framing of bubbles and shares as movable, resizable objects arranged in one shared AR-glasses-style space, which only holds together if every object type shares one system.
The exception is UI chrome such as toolbars and cursor labels, which stays viewport-relative, outside the canvas object model.

## Disclosure: media is visible at the SFU

Group-call audio and video are decrypted at the LiveKit SFU to be selectively forwarded and mixed to other participants, and that decrypted media is visible to whoever operates the deployment, official instance or self-host.
This is stated plainly rather than left implicit: group calls are a primary use case, and the project's transport-only encryption stance already places the operator inside the trust boundary for text, and equally for voice, video, and screen share.
No end-to-end media encryption ships in v1.
