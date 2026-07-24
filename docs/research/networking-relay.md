# Push Relay and Mobile Connectivity

Status: pre-implementation research.
Scope: registration and the scoped key model, APNs alongside FCM, exact push payload contents and privacy boundaries, wake-up semantics, iOS background execution and PushKit, delivery volume, rate limiting, and relay cost.

## 1. Registration and the scoped key model

Reuse check-in-relay's model almost unchanged: a self-hosted server calls `POST /v1/register` once, gets a scoped bearer key returned exactly once, and the relay stores only its SHA-256 hash.
The key now authorizes sends through both FCM and APNs rather than one channel, so there is no separate per-platform key; the send call carries a `platform` field per message, set by the home server, since it already knows how each device registered.
The official hosted instance registers through the same path and key model as any self-hosted server, so the main server codebase has exactly one send path rather than a direct-to-FCM path plus a relay path; a deliberate simplicity choice, at some latency cost for the official instance's own users.

I deviate from one line in the brief: "maintain the association between a self-hosted server and the user's mobile devices" as a relay responsibility.
The security report already flagged this line; I confirm the flag and reject the literal reading.
A persistent devices table, per-user, per-device rows, turns a stateless forwarder into a second copy of the home server's device registry and buys nothing the current shape does not already deliver: `/v1/send` already carries whatever tokens the caller wants notified, batch by batch, exactly as check-in-relay does today.
The underlying need is satisfied by the home server tracking its own devices and passing tokens at send time; the relay stays a dumb forwarder with no devices endpoint at all.
Risk: a self-hoster cannot ask the relay which of their devices are registered, but that question belongs to the home server's device list, not the relay's.

## 2. APNs alongside FCM

Today's plan uses FCM's APNs bridge for iOS, which works for check-in-relay but adds latency, an extra failure point, and blocks APNs-native features this app needs: VoIP pushes, communication notifications, interruption levels.
Verdict: add a direct APNs provider path, `internal/apns`, mirroring `internal/fcm`'s shape (`Message`, `Result`, `Sender.Send`), authenticated with Apple's token-based provider API, one `.p8` signing key plus Team ID and Key ID, generating a short-lived ES256 JWT cached in memory and rotated at most every twenty minutes, well inside Apple's one-hour validity window.
This is one long-lived credential, not a certificate that expires yearly, keeping credential management as close to the Firebase service account's load-once-keep-forever model as APNs allows.
`/v1/send` routes each message by its `platform` field to the FCM or APNs sender, and both map their distinct failure vocabularies, `UNREGISTERED` for FCM, `410`/`BadDeviceToken` for APNs, to the same delivered/unregistered/error result the home server already prunes on.

## 3. Payload contents and what stays private

The relay never carries plaintext title or body text; the security report already committed to this, and the wire format is built around it.
`/v1/send` accepts a batch of `{token, platform, kind, ciphertext, collapseId, priority}`, where `kind` is one of `message`, `mention`, `call`, or `wake`, and `ciphertext` is the home server's encryption of the real notification content to the device's push public key.
The relay wraps that ciphertext in a platform-native envelope and never inspects it.
On iOS this is a `mutable-content: 1` push carrying a static fallback alert (app name plus "New message") and the ciphertext in a custom data key; a Notification Service Extension decrypts on-device and replaces the fallback text, the pattern Signal and WhatsApp both use.
On Android this is an FCM data-only message with no `notification` block, so the app always runs its own code to decrypt and build the visible notification rather than trust a server-rendered one.
What the relay stores or logs: the hashed server key, an opaque push token, the coarse `kind`, and per-request delivered/unregistered/error counts, matching check-in-relay's log discipline.
What it never sees: message content, sender or recipient identity beyond an opaque token, channel or server names.
Residual risk, already accepted at the security level: send timing and volume are still visible to the relay operator, a traffic-analysis exposure ciphertext-only payloads do not close; batching and jitter are future work.

## 4. Wake-up semantics

A push is a trigger, never a source of truth.
Every `message` and `mention` push, once decrypted client-side, causes the app to open a connection to its home server and fetch the authoritative content rather than display anything derived purely from the push payload; this keeps the relay from ever needing to be consistent or ordered, only prompt.
The `wake` kind covers the case with no user-visible content at all: a silent APNs `content-available` or FCM data push telling a backgrounded app to reconnect and sync, used only when the WebSocket is not already live, never as a keepalive mechanism, since that would multiply relay volume for no benefit.

## 5. iOS background execution and PushKit

Voice and video calls need `PKPushTypeVoIP` plus CallKit; nothing else on iOS should touch it.
Regular remote notifications get a best-effort delivery window and roughly a thirty-second background budget for the Notification Service Extension, enough to decrypt a message preview but not enough to reliably stand up a WebRTC connection and ring the user in time.
VoIP pushes bypass that throttling and guarantee background execution, exactly what an incoming call needs and why Apple restricts the entitlement: every VoIP push must report an incoming call to CallKit synchronously, and Apple has revoked the entitlement from apps that used it for other purposes since its 2015-2016 enforcement action against VoIP-push misuse.
Verdict: `kind=call` routes through a separate APNs topic (`<bundle-id>.voip`) and push type, reports to CallKit on every delivery with no exceptions, and no other kind ever uses PushKit.
A wrong call here is an App Store risk, not just a UX regression, so the CallKit-report invariant needs a test, not a code review comment.

## 6. Delivery volume and rate limiting

Target scale for planning, not a growth promise: thousands of self-hosted servers and low hundreds of thousands of devices at a mature v1, each device generating roughly ten to a few dozen background push events a day, since a connected client gets messages over its own WebSocket and never needs push.
That lands around the low tens of pushes per second on average, with bursty peaks perhaps five to ten times higher, comfortably inside what one small Go process handles.
check-in-relay's fully serial one-token-at-a-time send loop is worth fixing now: replace it with a small bounded worker pool, roughly twenty concurrent sends per `/v1/send` call, so one slow FCM or APNs round trip does not serialize the batch, keeping the request synchronous end to end; a full async queue is deferred until real traffic data justifies the added operational surface.
Rate limits extend check-in-relay's existing knobs: registration stays at five per hour per IP, per-key send limits rise roughly tenfold for messaging volume (600 per minute per key, burst 200), and a new per-device cap (30 per minute, burst 10) stops one compromised or buggy server-side account from push-bombing a single victim's phone even while that server's aggregate key limit still has headroom.
Call pushes get their own small, separate cap rather than sharing the per-device bucket, since a dropped call push is a missed call, not a delayed message, but still needs a low ceiling to block call-bombing as a harassment vector.

## 7. Cost profile

Both FCM and APNs are free to send through at any volume; the relay's marginal cost per push is zero on both platforms, unchanged from check-in-relay's own cost note.
Real cost is the same small always-on compute footprint: one Go binary plus Caddy, comfortably under the 128 MB per-container limits check-in-relay already runs with, on a few-dollar-a-month VPS.
The only scale-driven cost is compute and bandwidth for concurrency, not a per-message fee, so more registered servers does not produce a growth curve in relay operating cost the way it would for a paid push provider.

## Open questions

- Whether self-hosters who want zero relay dependency at all (LAN-only, desktop-first deployments) get a documented no-push mode, versus always registering even if push traffic stays at zero.
- Whether the maintainer's own APNs bundle ID needs separate production and sandbox credential handling for TestFlight builds of the official app, or whether TestFlight distribution is out of scope for v1.
