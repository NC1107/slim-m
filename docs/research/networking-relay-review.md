# Push Relay and Mobile Connectivity: Adversarial Review

Status: pre-implementation critique of `docs/research/networking-relay.md`.
Scope: the same axes the report itself covers, plus consistency against the brief and the sibling research reports it should have been reconciled with (`security.md`, `realtime-sync.md`, `backend.md`, `appstore.md`), plus a direct read of the `check-in-relay` reference repository the report extends.
Severity is reserved for "critical" only where the finding would force a redesign before implementation starts.

## Summary

The report is careful and mostly internally consistent, and several of its calls are correct: rejecting a relay-side devices table, moving to token-based APNs auth, and fixing check-in-relay's serial send loop are all the right instincts.
But the report was written without fully reconciling with two sibling documents in the same folder, and one of those mismatches is foundational: `realtime-sync.md` describes a push-payload policy that directly contradicts this report's own "never plaintext title or body" privacy boundary.
The report also inherits check-in-relay's trust model unchanged into a much higher-stakes context: check-in-relay's key is scoped to a low-consequence check-in event, while this report reuses the exact same "any valid key can target any token" shape for a messaging platform where a stale or leaked device token becomes a standing harassment channel with no relay-side revocation.
Finally, several of the concrete numbers in the report (the worker pool size, the per-key send cap, the "10x" comparison) are asserted without being checked against the actual code they extend or the scale the brief's own "Discord-like" feature set implies, and the code itself confirms at least one of these does not do the arithmetic the report claims.

## Critical findings

### 1. The payload privacy boundary contradicts a sibling report, not just a stylistic gap

Target: networking-relay.md section 3, "the relay never carries plaintext title or body text... ciphertext... never plaintext title or body," and section 3's claim that "the relay, APNs, and FCM all blind to content."

Weakness: `realtime-sync.md`'s "Push notification triggering" section states the opposite policy for the majority of v1 traffic: "push payloads never carry message content for E2E-encrypted conversations... for plaintext conversations only, a short preview can ride in the push payload itself."
Since `security.md` explicitly defers E2EE for all of v1 ("end-to-end encryption is explicitly deferred, not adopted... opt-in E2EE DMs later"), every v1 conversation is a "plaintext conversation" under `realtime-sync.md`'s own framing, meaning that report's design puts a short, human-readable preview into the push payload for essentially all v1 messages.
A preview riding in the push payload for OS-level display is not compatible with the ciphertext-plus-Notification-Service-Extension architecture this report designs; the two describe different wire formats, different client-side code paths, and different sets of parties who can read the content.
If a preview is delivered as a native FCM `notification` block or an APNs `alert` dict, FCM and APNs read plaintext content directly, the opposite of what this report and `security.md` both commit to.

Failure mode: whichever specialist's design gets implemented first becomes the de facto contract, and the other report's stated invariant silently breaks.
If the client team builds against `realtime-sync.md`'s "short preview" language, message content flows through Apple's and Google's servers in the clear for the entire v1 launch, contradicting the metadata-minimization commitment this report and `security.md` both make in writing.
If the client team builds against this report's ciphertext-only design instead, `realtime-sync.md`'s stated behavior for plaintext conversations is simply wrong and needs to be retracted, and the debounce/live-connection-check logic in that report needs to be re-verified against an always-encrypted payload.

Resolution: reconcile the two reports explicitly before any push code is written.
Pick one policy: either the payload is always ciphertext regardless of whether the specific conversation happens to be E2EE (the stronger, more defensible choice given the stated adversary set includes "the relay operator inferring metadata"), or `realtime-sync.md`'s preview language is corrected to say the preview is itself encrypted to the device push key and decrypted client-side, not sent as native OS notification text.
Either way, the resolution needs to be written down in both documents, not left implicit.

### 2. A "scoped" key is not scoped to anything, and the relay has no way to revoke a specific token

Target: networking-relay.md section 1's key model and the "Relay device association scope" recommendation that keeps the relay a stateless forwarder with "no devices endpoint at all."

Weakness: confirmed by reading `internal/api/send.go` in `check-in-relay`: `handleSend` authenticates the caller's key, then accepts and forwards whatever `Token` values appear in the request body with zero check that those tokens were ever associated with that key, or with any key.
The relay's only authorization boundary is "does this bearer key exist and is it under its rate limit," never "is this key allowed to push to this specific device."
Because `POST /v1/register` is self-serve and only IP-rate-limited (five per hour by default in `internal/config/config.go`), obtaining a valid key is cheap for anyone, including someone who is not the operator of any real chat server at all.
Once a self-hosted server (or a malicious actor posing as one) has learned a device's push token, by receiving it as a legitimate member, by a former admin retaining it after a ban, or by any other leak, nothing in this design stops that token from being pushed to indefinitely, from a key that has nothing to do with the server the user is still a member of.

Failure mode: a user is banned from, or simply leaves, a self-hosted server.
`security.md`'s device-session model revokes that user's session and push registration on the home server that banned them, but the relay itself was deliberately designed to hold no device state to revoke, so a malicious or simply vindictive former admin who retained the token before the ban can continue submitting `kind=call` or `kind=message` pushes for that exact token indefinitely, through their own still-valid key, completely outside the victim's control and outside the banning server's ability to stop it.
The per-device rate cap this report proposes (30/min, burst 10) slows this down but does not stop it, and a repeated `kind=call` push at even a low ceiling is, by this report's own words elsewhere, "a missed call, not a delayed message" turned into a harassment vector, not a mitigated one.
The user's only recourse is reinstalling the app to obtain a new push token, a mitigation this report never states and the security report does not mention either.

Resolution: this does not require the devices table the report correctly argues against.
A much lighter fix closes the gap: bind each token to the key that first presented it (a single row per token, not a full device registry with metadata) and reject sends for a token from any other key, so a departed server's key cannot reach a token it no longer has any relationship to once the home server stops presenting it, and a compromised key's blast radius is limited to the tokens it actually registered rather than every token that has ever transited the relay.

### 3. The wake-then-fetch design has no answer for a self-hosted server that is not publicly reachable

Target: the brief's "wake the mobile application so it can securely connect directly back to the user's chosen self-hosted server," and this report's section 4 wake-up semantics, which take that reachability for granted.

Weakness: `security.md` explicitly treats a non-publicly-reachable deployment as a first-class supported shape: "LAN-only desktop use may opt into trust-on-first-use identity pinning," distinct from the "public domain with a valid certificate... required for any mobile-reachable server" case.
A very common real-world self-hosting shape sits between those two: a server on a home network behind a router with no port forwarding and no dynamic DNS, reachable from the LAN but not from the public internet, which is not the same as the deliberately LAN-only case `security.md` names, and is one of the single most common sources of support friction in comparable self-hosted projects.
This report never once discusses server-side public reachability as a precondition for the wake architecture to have any value at all; it treats "connect directly back" as always possible once the push arrives.
The report's own open question 1 gestures at "self-hosters who want zero relay dependency" but frames it as an opt-out preference, not as the reachability failure case it actually is, and `backend.md` independently states the client already plans a `PushSender` trait "swappable or disableable per self-hoster," a mechanism that could resolve this, but this report never cross-references it or proposes when a server should use it.

Failure mode: a self-hoster runs the server on a home Fedora box exactly as the brief's "Fedora is the primary desktop testing environment" language invites, with no port forward configured.
The server registers with the relay successfully (registration is outbound-only, so it works fine) and sends wake pushes successfully (also outbound-only).
The user's phone leaves the home network, receives a wake push, and has no reachable address to connect back to; the push fires, the notification may even show a generic "New message" fallback, and the app then fails silently or shows a connection error every single time, for a class of deployment the brief and `security.md` both anticipate as valid.

Resolution: state this precondition explicitly as a documented constraint on the wake architecture, and give self-hosters a concrete decision at setup time: either the server must be reachable inbound (with the Caddy/DDNS-friendly path `security.md` already assumes for the TLS story), or push registration should be skipped entirely via the `PushSender` disable path `backend.md` already designed, with the client falling back to foreground-only, LAN-connect, or manual-refresh behavior instead of registering for a wake it can never fulfill.

## Major findings

### 4. The worker-pool fix bounds throughput, not the tail latency that made the serial loop a problem in the first place

Target: networking-relay.md section 6, "replace it with a small bounded worker pool, roughly twenty concurrent sends per `/v1/send` call... keeping the request synchronous end to end."

Weakness: `internal/fcm/fcm.go`'s `Send` method confirms the underlying HTTP client has a fifteen-second timeout per call, and `internal/config/config.go`'s `MaxMessages` defaults to 500 tokens per request.
Twenty concurrent workers against 500 tokens is twenty-five sequential rounds; if a batch happens to hit a slow or degraded FCM/APNs window (not a hypothetical, both providers have real-world slow periods), worst-case latency for one `/v1/send` request is bounded only by 25 times 15 seconds, over six minutes, still returned synchronously to the caller.
The report frames this change as strictly an improvement over the fully serial loop, but a fully serial loop with a smaller batch (check-in-relay's actual usage pattern) was never exposed to this failure mode at anywhere near this severity; messaging's larger batches make the tail-latency problem materially worse even after the proposed fix, not solved by it.

Failure mode: a home server sends a large batch (a busy channel notifying many backgrounded members at once) during a window where FCM or APNs is degraded.
The home server's own HTTP client is blocked for minutes waiting on a single relay response it has no way to partially consume, and if that client has any reasonable timeout of its own (most do), it gives up and cannot tell which of the 500 tokens actually got delivered, since the relay's all-or-nothing response never arrives.

Resolution: cap worst-case latency directly, not just improve average throughput; either bound total request time with a hard deadline that returns partial results for whatever completed, or move to an accept-and-poll model for batches above a size threshold, well before "real traffic data" forces the issue, since the tail-latency mechanism is fully predictable from the code today without waiting for production evidence.

### 5. In-memory rate limiting silently stops enforcing correctly the moment the relay is not a single instance, and this report's own recommendation makes that more likely

Target: networking-relay.md section 6's rate-limit numbers, layered on `internal/ratelimit/ratelimit.go`'s design, "sufficient for a single-instance relay; a multi-instance deployment would move this to a shared store" per that file's own doc comment.

Weakness: the report never restates or re-affirms this single-instance constraint anywhere, despite adopting the exact same in-memory limiter for four separate limit types (registration, per-key send, per-device, per-call).
At the same time, section 1's recommendation to route the official hosted instance's own traffic through this same relay path increases the operational pressure to eventually run the relay as more than one process for availability, which is precisely the condition under which every one of these limits silently multiplies by the replica count with no error, no log line, and no test that would catch it.

Failure mode: the maintainer adds a second relay replica behind a load balancer for a routine zero-downtime deploy or basic redundancy, unaware that this quietly doubles every effective rate limit, including the per-device call-push cap this report calls out by name as the harassment-abuse backstop.

Resolution: either state single-instance-only as a hard, documented operational constraint with an explicit "do not scale this horizontally without a shared limiter store" warning, or follow `realtime-sync.md`'s own precedent of making the limiter "an injectable interface so the official hosted instance can swap in a shared-store implementation," which that sibling report already committed to for the main server's limiter but this report never adopts for the relay's.

### 6. Registration has no global ceiling, only a per-IP one, against a shared credential that serves every self-hosted server at once

Target: networking-relay.md section 6's registration limit (five per hour per IP, unchanged from check-in-relay) and section 7's "cost stays near zero" framing.

Weakness: per-IP throttling bounds one address, not one actor; rotating through cheap or free IP pools to mint effectively unlimited independent keys is a well-understood, low-effort attack against exactly this shape of limiter, and each minted key then carries its own full 600/min, burst-200 send allowance under the report's proposed numbers.
Every self-hosted server's traffic, and the official instance's own traffic per section 1, ultimately funnels through the same one Firebase project and the same one APNs Team ID, so aggregate abuse across many cheaply-minted keys is not just a relay capacity question, it is a shared-credential standing question with Google and Apple.

Failure mode: an attacker mints a large number of keys from rotating IPs and drives aggregate send volume against the one shared FCM project or APNs topic high enough to trigger Google's or Apple's own abuse throttling or a manual account review, degrading or freezing push for every legitimate self-hosted server on the platform simultaneously, not just the attacker's traffic.
Section 7's "marginal cost stays zero" claim does not account for this shared-credential availability risk at all, only per-message billing.

Resolution: add a global (not just per-IP) registration ceiling and monitor aggregate send volume against the shared FCM/APNs credentials specifically, with an explicit incident plan for what happens if Google or Apple ever throttles the shared project, since that failure mode takes down push for the entire platform at once, not one server.

### 7. `kind=call` and mandatory CallKit are not scoped away from the brief's own persistent group voice channels

Target: networking-relay.md section 5's "VoIP PushKit for calls" verdict, against the brief's explicit "Group Chats: Voice calls" and Discord-style always-on voice channel model.

Weakness: the report defines `kind=call` and its CallKit-ringing requirement only in terms of "voice and video calls" generically, with no boundary excluding the ambient case the brief clearly wants: a persistent, always-open group voice channel that members freely join and leave, the way Discord voice channels work, which is explicitly the interaction model the brief asks this project to replicate.
CallKit's full-screen ringing UI is designed for telephony-style incoming calls, not for "a friend joined the hangout channel," and Apple's own 2.5.4 guideline, which the report and `appstore.md` both cite for the 2015-2016 VoIP-push enforcement history, is about entitlement misuse for exactly this kind of non-call use.

Failure mode: implemented literally, every join to an already-active group voice channel triggers a CallKit ring on every other member's phone, an obnoxious and almost certainly App-Store-risky UX regression for the platform's own signature Discord-like feature; implemented defensively to avoid that, engineers may end up routing legitimate group-DM call invites through the ordinary `message` kind instead to dodge the ringing behavior, quietly losing the reliable-wake guarantee VoIP push exists to provide for the one case (an actual incoming call) that needs it.

Resolution: state explicitly which call shapes get `kind=call` (1:1 calls, and explicit "start a call" invites in small DMs or channels) versus which never do (joining an already-active, persistent group voice channel), and have this boundary reviewed against the same App Store scrutiny `appstore.md` already applies to VoIP-push misuse.

### 8. The push-payload encryption construction is a black box, despite being this report's own stated scope

Target: networking-relay.md section 3's "ciphertext is the home server's encryption of the real notification content to the device's push public key," and `security.md`'s statement that the same X25519 identity keypair "also encrypts push payloads... and anchors future E2EE."

Weakness: the report's own scope line names "exact push payload contents" as something it covers, but never specifies the actual construction: which asymmetric scheme (sealed box, HPKE, raw ECIES), how nonces are generated and whether reuse is possible, or how the home server obtains and caches each device's push public key.
More specifically, reusing the same X25519 identity keypair that `security.md` earmarks for future E2EE as the push-encryption key, without a stated domain separator, mixes two different protocols under one keypair, a recognized cryptographic anti-pattern that a clean HPKE `info` string or a dedicated push-specific subkey avoids at near-zero cost.

Failure mode: without a specified construction, two different engineers (relay-side ciphertext generation, client-side NSE decryption) can each make reasonable-looking but incompatible implementation choices, discovered only when real devices fail to decrypt real pushes; and if the same static key is later reused for actual E2EE session establishment without explicit domain separation, a cross-protocol confusion attack becomes a live concern rather than a theoretical one.

Resolution: specify the exact construction (a well-reviewed library primitive such as libsodium's sealed boxes or an HPKE ciphersuite, not a bespoke scheme) and either derive a separate push-specific subkey from the identity key with an explicit domain-separation label, or state plainly why sharing the raw identity key across both purposes is judged safe, so implementers are not left to infer the answer from two separate reports.

### 9. The per-key send cap is sized for "a self-hosted server," not for the large public communities the brief explicitly invites

Target: networking-relay.md section 6's proposed 600/min, burst-200 per-key send limit.

Weakness: the brief asks this platform to "replicate the base level functionality of Discord" for group chats, which implies some self-hosted servers will be large public communities, not just the "handful of active users" case the brief separately names as the lightweight-default target.
A single busy server with a few thousand members, even a modest fraction of them backgrounded on mobile during an active discussion with mentions, can plausibly need to notify more than 600 device tokens within one minute of ordinary peak activity, well within normal Discord-like usage, not an abuse scenario.
The report proposes exactly one static number for every server, with no tiering by registered device count or any admin-adjustable ceiling.

Failure mode: a large, entirely legitimate self-hosted community server hits its own key's rate limit during ordinary peak chat activity, and some members simply stop receiving push notifications for messages that already happened, with no indication to the server operator of why, since the limit is invisible relay-side state the home server was never told how to anticipate.

Resolution: either tier the per-key limit to the number of devices the server has actually registered pushes for, or expose the limit and current usage through the admin surface so an operator of a large community can see they are near the ceiling before users start silently missing notifications, rather than discovering it as an unexplained reliability regression.

### 10. The always-encrypt-to-device-key design is real complexity pushed onto every self-hosted server for a threat model v1 barely has

Target: the combined effect of networking-relay.md section 3 and security.md's deferred-E2EE verdict, against the brief's "a self-hosted server with only a handful of active users should remain extremely lightweight."

Weakness: because `security.md` defers E2EE for all of v1, every home server already stores every message as plaintext in its own database, fully visible to the operator, who `security.md` itself places "inside the content boundary" as a trusted party.
The per-device push-key encryption pipeline this report designs protects that same content from exactly one additional party, the relay, at the cost of every self-hosted server, down to a single-user hobby deployment, having to implement and maintain asymmetric encryption, per-device key lookup and caching, and a platform-specific envelope format, none of which check-in-relay's original plain title-and-body payload required.
This is a legitimate protection to want against the relay specifically, but the report never weighs it as a cost against the brief's explicit "extremely lightweight" bar for small self-hosted instances, nor considers a cheaper middle ground.

Failure mode: a hobbyist running a two-person server for friends now needs correctly-implemented push cryptography in their server's send path before a single push notification works at all, a meaningfully higher implementation bar than check-in-relay ever asked of check-in-relay's own integrators, for a threat (the relay operator reading message previews) that is real but narrower than the "every self-hosted operator already has full plaintext access anyway" baseline this same document set has already accepted.

Resolution: this finding does not argue for dropping the encryption, only for stating its cost honestly and revisiting the scope once finding 1's cross-report conflict is resolved; if `realtime-sync.md`'s "plaintext conversations" carve-out is the actual intended v1 policy, most of this complexity may not be needed for launch at all, which is exactly why finding 1 has to be resolved first.

## Minor findings

### 11. Routing the official instance through the relay trades an unforced single point of failure for code-path simplicity that a shared library would already buy

Target: networking-relay.md section 1, "the official hosted instance registers through the same path and key model as any self-hosted server... at some latency cost for the official instance's own users."

Weakness: `internal/fcm/fcm.go`'s own doc comment already shows the pattern that avoids this trade-off: "this is a deliberate copy of the send path in the Check-In server's internal/push package... Go forbids importing another module's internal/, and keeping a copy leaves the relay independent."
The same copy-or-share-a-package approach gets the official server one send path without also making its own users' push reliability depend on the relay's uptime, deploys, and database health, none of which the official server otherwise needs to depend on for anything else.

Failure mode: a relay incident, a bad relay deploy, or relay database corruption now also breaks push for the flagship official service, a dependency the official server did not previously have and does not need, purely to keep the send-path code in one place rather than two coordinated copies.

Resolution: give the official server its own direct FCM/APNs client sharing the same package as the relay's, the same pattern already used to avoid a cross-module `internal/` import, instead of routing its own users' traffic through the relay's network hop and failure domain.

### 12. A device's push token is a stable identifier shared unmodified across every unrelated server it joins

Target: the registration and send model as a whole; no single section names this, which is itself part of the gap.

Weakness: the same platform push token necessarily gets handed to every self-hosted server a user joins, since each server independently needs to reach that device, and the relay's design deliberately avoids correlating tokens across requests, which is the right call for the relay itself.
But nothing stops two separate self-hosted operators, or one operator running multiple servers, from comparing the identical token value they each separately received and inferring that the same physical device, and therefore likely the same person, is present on both of their otherwise-unrelated communities.

Failure mode: a user who deliberately keeps two server memberships unlinked (different display name, different identity, on two communities they do not want connected) can have that separation quietly undone by any two admins willing to compare notes on a token value neither of them was supposed to treat as a durable identifier.

Resolution: at minimum, name this as an accepted residual risk alongside the timing/volume traffic-analysis risk the report already accepts in section 3, since it is the same category of problem (a token acting as a correlation handle) and deserves the same explicit treatment.

### 13. The single serialized SQLite writer is an unflagged throughput ceiling worth naming even though it is not urgent

Target: `internal/keys/keys.go`'s `Store`, `db.SetMaxOpenConns(1)`, and the unconditional `UPDATE keys SET last_used_at` on every single `Verify` call, i.e. every `/v1/send` request.

Weakness: at the volumes this report itself estimates, low tens of pushes per second aggregated into batched requests, this ceiling is very unlikely to bind, but the report never mentions it as the first thing to profile if real traffic exceeds plan, despite naming several other numbers (worker pool size, rate limits) as exactly that kind of forward-looking sizing note.

Failure mode: if actual request-per-second volume (not push-per-second, which batches) grows faster than push-per-second volume, for example because home servers start sending many small batches instead of few large ones, the single-writer SQLite connection becomes the actual bottleneck before the worker pool or the rate limiter numbers do, and nothing in the report would have predicted that.

Resolution: name this explicitly as a known ceiling alongside the other sizing notes in section 6, even if the conclusion remains "not a concern at planned scale."

### 14. The report's own "10x" framing does not match the code it is extending

Target: the condensed recommendation's "send limits roughly 10x higher than check-in-relay's defaults," against `internal/config/config.go`'s actual default, `SendPerMinute: getint("RELAY_SEND_PER_MINUTE", 120)`.

Weakness: 600 divided by 120 is 5, not roughly 10; the "10x" framing appears to compare against a different baseline than the one actually shipped in the reference repository's default configuration.

Failure mode: a minor sizing-math error on its own, but the kind of unchecked number that gets copied into a config file or a README as "10x check-in-relay defaults" and then quietly misleads whoever tries to reason about headroom later.

Resolution: recompute against the actual default (120/min, burst 60) and either correct the "10x" language or the target number, whichever was the intended anchor.

### 15. Android has no stated fallback when on-device decryption fails, unlike iOS's guaranteed generic alert

Target: networking-relay.md section 3's iOS path ("a static fallback alert... and the ciphertext in a custom data key") against its Android path ("an FCM data-only message with no `notification` block, so the app always runs its own code to decrypt and build the visible notification").

Weakness: iOS's envelope carries a baked-in fallback alert independent of whether on-device decryption succeeds, so a broken or delayed decrypt still shows something.
Android's data-only design has no equivalent baked-in fallback; the app itself is entirely responsible for producing any visible notification at all, and the report never states that a decrypt failure (corrupted local state, a missing key after a reinstall, a race with an app update) must still produce a generic fallback notification.

Failure mode: an Android decrypt failure can mean the user receives no notification at all, silently, with no OS-level safety net the way iOS has one, directly undermining the reliability goal the wake architecture exists to serve.

Resolution: require the Android client to show a generic fallback notification on any decrypt failure, mirroring the guarantee the iOS path already gets for free from the platform envelope.

### 16. No mention of the stale-or-cancelled-call CallKit reporting requirement, a common real-world PushKit failure mode

Target: networking-relay.md section 5's "every VoIP push must report an incoming call to CallKit synchronously."

Weakness: the report states the reporting requirement correctly but does not mention the specific case that most often breaks it in practice: a caller cancels before the callee's device processes the push, or the call has otherwise already ended by the time the VoIP push arrives, and Apple's rules still require the app to report the call to CallKit and then immediately end it, rather than silently dropping the report because the call is stale.

Failure mode: an implementer reads "report to CallKit on every delivery" and handles the common case correctly but skips reporting for a push that arrives after the call already ended, since it feels pointless to ring for a call that is no longer live, which is exactly the omission Apple's enforcement targets.

Resolution: call out the stale/cancelled-call case explicitly as its own required test, not an implicit instance of "every delivery," since this report already correctly insists the CallKit invariant "needs a test, not a code review comment."

### 17. The worker pool bounds per-request concurrency, not concurrency across simultaneous requests

Target: networking-relay.md section 6's "small bounded worker pool, roughly twenty concurrent sends per `/v1/send` call."

Weakness: the twenty-worker cap applies within one request; nothing in the report describes a ceiling on how many requests the relay processes concurrently, so a burst of many self-hosted servers all sending large batches at once, for example after a shared upstream outage where every server catches up simultaneously, can still multiply goroutine and outbound-connection count well beyond what one twenty-worker pool implies, with no admission control anywhere in the design.

Failure mode: a correlated event (a widely-used dependency outage, a mass reconnect after relay downtime) causes many servers to send large batches at the same moment, and the relay's actual peak concurrency is the per-request pool size times the number of simultaneous requests, an unbounded product the report's numbers never account for.

Resolution: add a process-wide concurrency ceiling (a global semaphore ahead of the per-request worker pools) so a correlated burst degrades gracefully (queuing or backpressure) rather than spiking unbounded goroutine and connection counts.

## Closing note

The report's individual technical calls, token-based APNs auth, rejecting a devices table's literal reading, fixing the serial send loop, are each reasonable in isolation.
The two failures that matter most are coordination failures: a genuine, unreconciled contradiction with `realtime-sync.md` over whether push payloads ever carry plaintext, and a security posture inherited unchanged from check-in-relay's low-stakes check-in context into a messaging platform where an unrevocable, unscoped push target is a standing harassment surface, not just a metadata nicety.
Both are the kind of foundational choice that gets expensive to change once client-side NSE code and server-side send code exist on both sides of the wire format.
Neither requires abandoning the report's overall shape, a lightweight relay extending check-in-relay remains the right instinct, but both need to be resolved in writing before implementation starts, the way `database.md` did the work of reconciling with its siblings elsewhere in this document set.
