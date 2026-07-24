# Adversarial Review: Security Architecture and Threat Model

Status: pre-implementation red-team of `docs/research/security.md`.
Reviewer stance: attack the plan before code exists, name a specific target and a concrete failure mode for each challenge, and reserve "critical" for issues that force a redesign.
Reference repositories were consulted to verify claims; `check-in-relay` behavior cited below was read directly from source.

## What holds up

Several claims check out against the reference code and adjacent reports.
The relay-forwards-plaintext concern is real: `check-in-relay`'s `internal/api/send.go` and `internal/fcm/fcm.go` (line 108) do send `title` and `body` in an FCM `notification` block today, so the ciphertext-only redesign genuinely reduces what the relay and platforms see.
The scoped, SHA-256-hashed, revocable key model the report reuses is accurate (`internal/keys/keys.go`).
Opaque server-side session tokens over stateless JWTs is the right call for a stateful hub, and the deny-by-default single-evaluator permission model is sound.
The magic-byte attachment validation, EXIF stripping, pixel caps, and unfurling-off-by-default posture are all correct instincts.
These are not the focus of the rest of this review.

## Critical

### C1. Ed25519 identity pinning cannot defeat an active MITM under the Caddy TLS-termination architecture

Target: the transport-security verdict, which claims a pinned long-lived Ed25519 server identity key "defeats a certificate-swapping MITM," combined with the recommendation to ship Caddy auto-TLS as the default self-host path.
These two recommendations undermine each other, and as written the headline defense does not defend the stated threat.
Concrete failure: an active attacker who obtains a fraudulent-but-CA-valid certificate for the server's domain (compromised or mis-issuing CA, hijacked DNS-01, or a coerced ACME challenge) terminates TLS transparently and proxies the connection.
For the pinned identity key to stop this, the server must prove possession of the identity private key in a way bound to the specific client-facing TLS channel (a channel binding such as the TLS exporter or `tls-unique`).
If the server merely signs a client-supplied nonce, the MITM forwards the nonce to the real server, relays the real signature back, and the client sees a valid identity proof over the attacker's TLS session.
The architecture makes correct channel binding impossible: Caddy terminates TLS and the Rust application server sits behind it over localhost plaintext, so the app that holds the Ed25519 key never sees the client-facing TLS session and cannot bind its signature to it.
The report never specifies the identity handshake at all, so the central "trust survives certificate rotation" property is asserted, not designed.
Severity: critical, because making identity pinning actually MITM-resistant requires either terminating TLS inside the app (abandoning the recommended Caddy pattern) or building an application-layer authenticated channel keyed to the identity (a Noise-style handshake), both of which are transport-trust redesigns rather than section edits.
Resolution: specify a concrete identity handshake now, decide where TLS terminates in light of it, and stop claiming MITM resistance until the binding mechanism exists.

## Major

### M1. The Go server recommendation contradicts an already-decided Rust backend, taking the Go-specific supply-chain gates with it

Target: the server-language recommendation ("Adopt Go for server and relay") and the supply-chain policy (govulncheck and OSV-Scanner "for the server").
`docs/research/backend.md` firmly decides Rust/Axum for the main server and Go only for the relay, and lists Go's GC latency jitter as a reason to reject it for the stateful hub.
Concrete failure: govulncheck analyzes Go binaries and reports nothing useful about a Rust server, so the promised CI vulnerability gate for the server language simply does not run; the "single static CGO-free distroless binary" framing also describes Go, not a rustls Rust build.
The security posture mostly survives the swap, but the supply-chain section as written leaves the actual server language ungated.
Severity: major.
Resolution: defer the language call to the backend owner, rewrite the supply-chain gates around cargo-audit and cargo-deny (already specified in backend.md) for the server, and keep govulncheck/OSV-Scanner scoped to the Go relay.

### M2. Argon2id at 19 MiB collides head-on with the self-host memory budget and is an unauthenticated amplification DoS

Target: the Argon2id default of 19 MiB, t=2, p=1, described as "cheap for small servers."
`docs/research/backend.md` sets the combined idle budget at under 150 MB (server under 30 MB, Postgres 60 to 80 MB) enforced as compose `mem_limit` values, leaving roughly 40 MB of headroom.
Concrete failure: the login endpoint is unauthenticated and each password verification allocates 19 MiB; a handful of concurrent login attempts (two hashes already exceed the headroom, ten cost 190 MB) push a mem-limited container into the OOM killer, taking the server down for everyone.
Per-IP throttling does not save this, because credential-stuffing traffic arrives from many IPs (a botnet or proxy pool) and the memory cost is paid before any per-account lockout applies.
Severity: major, because the mitigation is a genuine tradeoff between weakening the hash, raising the lightweight memory target, or adding a global concurrency gate on hashing, and none of the three is stated.
Resolution: bound concurrent Argon2id evaluations with a small semaphore, size that bound against the container `mem_limit`, and document the interaction explicitly rather than calling 19 MiB unconditionally cheap.

### M3. Only attachment blobs are encrypted at rest, with a co-located key, against a threat model that scopes database and backup theft

Target: the residual-risk mitigation that encrypts attachment blobs and documents operator volume encryption, offered against the in-scope adversary "theft of a database or backups."
Concrete failure: message text, the primary content, stays plaintext in Postgres, so a stolen database or backup yields every message directly; the attachment encryption that is applied uses a key the self-hoster must keep on the same host, and any backup that includes that key (the common case) decrypts the blobs trivially.
Encrypting blobs with a co-located key provides almost no protection against the exact backup-theft adversary it is cited to mitigate, absent external key management that a self-hoster without a KMS will not have.
Severity: major, because the report presents this as a mitigation when it is closer to security theater for the scoped threat.
Resolution: either scope the threat honestly to "raw volume theft only, mitigated by operator disk encryption," or commit to real at-rest key separation; do not imply message confidentiality against DB theft that the design does not deliver.

### M4. The uniform "encrypt body, decrypt in a Notification Service Extension" model does not apply to VoIP call pushes

Target: the relay metadata-minimization design, which uniformly encrypts the notification body to the device push key and decrypts on-device via an iOS Notification Service Extension.
`docs/research/networking-relay.md` and `docs/research/appstore.md` both require `kind=call` to travel as a PushKit VoIP push that reports to CallKit synchronously on every delivery, an Apple-enforced invariant whose violation has cost apps the entitlement.
Concrete failure: VoIP pushes are delivered to the PushKit delegate in the main app, not to a Notification Service Extension, and the app must report an incoming call to CallKit before doing meaningful async work, so the NSE decrypt path the report describes cannot run for calls; a design that assumes it will either shows no caller identity or risks missing the synchronous CallKit report.
The report treats all pushes as one shape and never addresses the strictest, most compliance-sensitive one.
Severity: major, because a wrong call here is an App Store risk, not a UX regression.
Resolution: define the call-push path separately: report a generic incoming call to CallKit synchronously, then reconcile caller identity after the app connects back to the home server, and never route calls through the NSE model.

### M5. The LiveKit SFU trust boundary, token minting, and room authorization are entirely absent

Target: the permission model and the encryption verdict, which mention group calls route through a server SFU but never cover how room access is authorized.
`docs/research/media.md` commits to LiveKit and requires server-minted short-lived JWTs scoped by role and room, which is the actual authorization gate for all voice, video, and screen share.
Concrete failure: the report insists on opaque tokens and "no JWTs," yet the media plane is JWT-gated by design, and the report never maps the connect, speak, and screen-share permission flags onto LiveKit grants; a mismatch or an over-broad grant lets a member escalate into a room or track it should not publish to or subscribe to.
The single most sensitive real-time surface for privilege escalation after the canvas is unspecified in the security design.
Severity: major.
Resolution: add a media-authorization section covering room-id derivation, per-role grant scoping (publisher versus subscribe-only), token TTL, and identity nonce-ing on rejoin, and reconcile it with the "no JWT" stance as a distinct capability-token system.

### M6. The server identity key has no rotation or loss-recovery story, and loss is indistinguishable from an attack

Target: the "long-lived Ed25519 server identity key" that clients pin on first join.
Concrete failure: if a self-hoster loses that key (disk failure, container rebuild without volume persistence, restore from a backup that omitted it), every previously joined client sees a pin mismatch that is, by construction, identical to the certificate-swap MITM the pin exists to detect; the client cannot tell recovery from attack and either bricks for existing users or is trained to click through mismatches, which destroys the pin's value.
The report explicitly leans on this key surviving certificate rotation but says nothing about the key itself rotating or being lost.
Severity: major.
Resolution: define key persistence requirements in the compose volume set, a signed rotation mechanism (new key countersigned by the old, or an operator-authenticated re-pin flow), and clear client UX for the recovery-versus-attack case.

### M7. Account deletion is treated as a client feature, not reconciled with the append-only audit log or promoted to a protocol verb

Target: the invite-and-compliance recommendation to "add in-app account deletion" alongside report and block.
`docs/research/appstore.md` is firmer: Guideline 5.1.1(v) requires deletion as a mandatory verb in the wire protocol shipped in the reference server from day one, with a non-hiding fallback for third-party servers.
Concrete failure: the security design also mandates an append-only audit log and retains message history and moderation records, and it never reconciles "delete the account" with "the log is append-only and messages persist," so a naive implementation either leaves user content and identifiers behind (failing 5.1.1) or mutates the append-only log (breaking its integrity guarantee).
Severity: major, because this is both a compliance obligation and an unresolved data-model tension.
Resolution: specify deletion as a protocol verb, define exactly what is purged versus tombstoned versus retained (and how that interacts with the immutable audit log), and ship it in the reference server from v1.

### M8. The in-process rate limiter loses all lockout state on restart, and CAPTCHA-free credential stuffing at the official instance is left largely unmitigated

Target: the layered in-process token-bucket limits with per-IP and per-account login throttling, backoff, and lockout, plus the explicit rejection of CAPTCHA.
The reference limiter (`check-in-relay/internal/ratelimit`) keeps buckets in a process-local map with no persistence.
Concrete failure: every server restart or deploy resets all buckets and lockout counters, so an attacker times brute-force bursts around restarts; more importantly, per-IP throttling does nothing against distributed credential stuffing from a proxy pool, and with CAPTCHA rejected and no other second factor mandatory, the official instance's public login has no defense that survives IP rotation.
Severity: major for the official multi-tenant instance; the per-account lockout helps but turns into a trivial account-lockout denial-of-service against a targeted victim if tuned aggressively.
Resolution: persist or centralize lockout state for the official deployment (the report already allows a Redis path), and add a defense that does not depend on client IP such as proof-of-work on repeated failures or mandatory step-up, rather than dismissing CAPTCHA and stopping there.

## Minor

### m1. Relay metadata minimization delivers almost no privacy to official-instance users

Target: the claim that encrypting push bodies keeps the relay a dumb forwarder that "sees less than check-in-relay."
`docs/research/networking-relay.md` states the official instance registers through the same relay as any self-hoster.
Concrete failure: for official-instance users the same operator runs both the home server (which holds plaintext) and the relay, so the relay-versus-server metadata boundary is illusory for the largest single user population; the benefit is real only for self-hosters.
Resolution: scope the privacy claim to self-hosted deployments and state plainly that official-instance users trust one operator with both content and timing.

### m2. Browser-model attachment defenses do not bind a native Flutter client, and the real client-side decoder surface is under-addressed

Target: the attachment-safety reliance on Content-Disposition, nosniff, and strict CSP to neutralize stored XSS.
Concrete failure: the primary client is native Flutter, which does not parse CSP or honor Content-Disposition, so those controls protect only a hypothetical web surface; meanwhile the brief requires pasting and rendering images and GIFs inline on the canvas, so the client fetches and decodes attacker-supplied media directly, and server-side pixel caps do not protect the client's own Impeller/Skia decode path from a malicious frame or a client-side decompression bomb.
Resolution: keep the server-side controls for any web surface, but add a client-side decode budget (dimension and memory caps before decode) and treat the native image decoder as the actual live CVE surface for received and pasted media.

### m3. Integer bitfield permissions silently corrupt on Flutter web past 53 bits

Target: the permission model stored as an integer bitfield with an append-only flag set.
`docs/research/backend.md` weighs Flutter-web ergonomics, so a web target is plausible.
Concrete failure: Dart `int` compiles to a JavaScript double on web, exact only to 53 bits, so once the append-only flag set grows past bit 52 (Discord hit exactly this), permission checks on Flutter web silently lose high bits and mis-authorize, a subtle escalation or lockout with no error.
Resolution: represent permissions as a string or byte-array bitset in the wire format, or cap and document the 53-bit ceiling if web is ever in scope.

### m4. "Authorize every canvas mutation server-side" is not reconciled with the client's optimistic hot-path rendering

Target: the permission model's insistence that every Voice Canvas mutation is authorized and validated server-side.
`docs/research/flutter-client.md` and the media report build the canvas around an off-Riverpod hot path that renders local mutations optimistically before the server acknowledges them.
Concrete failure: the report mandates server authorization but never defines what the client does when the server rejects a mutation it already painted, so a rejected stroke or move leaves the local and authoritative states divergent, the exact class of bug the sequence-number work exists to prevent.
Resolution: specify the reject-and-rollback contract (server rejection carries the op id, client reverts to the last acknowledged authoritative state), and distinguish one-time per-session capability checks from per-op shape validation so the guarantee does not read as a per-packet bitfield re-evaluation.

## Gaps the specialist never addressed

The multi-device key model is inconsistent and undermines the "E2EE addable without a rewrite" promise.
The report says each user generates one X25519/Ed25519 identity keypair whose private half stays non-exportable in one device's secure enclave, and that this same key encrypts push payloads, yet `docs/research/networking-relay.md` encrypts push to the device push public key, and `docs/research/realtime-sync.md` flags multi-device-per-user as a day-one requirement.
A single per-user key locked in one enclave cannot decrypt push on the user's second device and cannot anchor multi-device E2EE, while a per-device key contradicts the per-user framing; either way, multi-device key distribution and cross-signing is precisely the hard, rewrite-inducing part the report claims to have pre-wired away, so the pre-wiring gives false comfort and even the v1 push-encryption target is under-specified.

Push payload size is unbudgeted.
APNs caps a notification at 4 KB and the design base64-wraps ciphertext inside the payload, so a preview-bearing encrypted body plus envelope can approach or exceed the limit; the report never states a payload budget or what happens on overflow.

Compromise of the official relay is not modeled as an attack, only metadata inference.
Because `kind` travels in cleartext, a compromised relay can fabricate `kind=call` wakes to ring every device (harassment and phishing) even though it cannot forge message content; the report's credential-isolation note addresses secret theft but not relay-originated abuse.

CSAM hash-matching for the official instance is raised only as an open question, despite the app-store report treating UGC moderation as a launch-blocking obligation, so the legal exposure the report itself names has no committed answer.

## Overall

The report is strong on the pieces that are language- and deployment-independent: session model, permission evaluation, attachment validation instincts, and the honest refusal to call TLS-only private.
Its weaknesses cluster where it meets the rest of the architecture it does not own.
The transport-trust claim collapses against its own recommended Caddy deployment (C1), the server-language and supply-chain recommendations contradict a decided Rust backend (M1), and the media plane, multi-device keys, call-push path, and account-deletion protocol are either unaddressed or inconsistent with the subsystems that do own them.
None of the deferrals (E2EE, SFrame, batching, jitter) are wrong, but the report repeatedly states a defense as achieved when only its intent is (identity pinning, at-rest encryption, cheap E2EE pre-wiring), and those overclaims are the most dangerous part of a pre-implementation plan because they invite building on a guarantee that does not exist.
