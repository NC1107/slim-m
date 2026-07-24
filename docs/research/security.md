# Security Architecture and Threat Model

Pre-implementation security design; each decision carries rationale, rejected alternatives, and residual risk.

## Scope and trust boundaries

Five technical trust boundaries: client to home server, client to relay, home server to relay, client to client media, and the build and supply chain.
A sixth is social: the self-hosted operator is trusted with stored content, because users deliberately create an account on that operator's server.
Adversaries in scope: network MITM, a malicious or compromised server, an abusive or privilege-escalating user, a malicious client sending crafted payloads, the relay operator inferring metadata, theft of a database or backups, and a supply-chain attacker.

## Transport security

Verdict: TLS 1.3 mandatory on every control and data connection, no downgrade below 1.2, modern cipher suites only; media uses WebRTC DTLS-SRTP, encrypted independently of TLS.
Every server carries a long-lived Ed25519 identity keypair separate from its TLS certificate; the client pins it on first join (fingerprint embedded in the invite), so trust survives certificate rotation and defeats a certificate-swapping MITM.
Self-hosters get automatic TLS via the check-in-relay Caddy pattern (one-line Caddyfile, auto Let's Encrypt), with a documented path through an existing proxy.
A public domain with a valid certificate is required for any mobile-reachable server, because iOS App Transport Security makes self-signed certificates hostile; LAN-only desktop use may opt into trust-on-first-use identity pinning.
Risk: a self-hoster who terminates TLS incorrectly exposes traffic, mitigated by shipping the Caddy default rather than manual certificate handling.

## Lightweight encryption: the verdict

The brief's phrase "lightweight encryption appropriate for a messaging application" is ambiguous and I flag it deliberately.
Verdict: strong transport encryption (TLS 1.3 plus DTLS-SRTP) is the mandatory v1 baseline; end-to-end encryption is explicitly deferred, not adopted, while the architecture is pre-wired to add opt-in E2EE DMs later without a rewrite.
Rationale: E2EE is the opposite of lightweight, would break or cripple stated requirements including server-side history, search, synchronization, moderation, and readable push notifications, and fights a trust model that already places the operator inside the content boundary.
The pre-wiring is cheap: every user generates an X25519 plus Ed25519 identity keypair on-device at account creation, the private key stays in the platform keystore or secure enclave, and the public key publishes to the home server.
That key also encrypts push payloads (see relay) and anchors future E2EE.
Rejected: full Signal-style Olm/Megolm E2EE for all channels (too heavy, breaks moderation and search) and no encryption at rest beyond TLS (leaves backups exposed).
For media, 1:1 calls stay peer-to-peer, effectively end-to-end via DTLS-SRTP; group calls route through a server SFU where the operator can access media, with SFrame E2EE as a later option.
Residual risk: a malicious operator or breach exposes stored messages, mitigated by encrypting attachment blobs and documented operator-side volume encryption, not by pretending TLS-only equals private.

## Authentication and session model

Passwords are hashed with Argon2id at a default cost of 19 MiB, t=2, p=1 (OWASP minimum), cheap for small servers and tunable up.
Verdict: opaque server-side session tokens, not stateless JWTs.
Rationale: the server is already stateful, a session lookup is one indexed query, and opaque tokens give instant revocation (required for device management) while avoiding every JWT footgun (alg confusion, key handling, un-revocability).
Each login issues a short-lived access token (about 1 hour) and a rotating 60-day refresh token, both 256-bit and stored only as SHA-256 hashes; rotation includes reuse detection, so a replayed old token revokes the whole family and catches theft.
A device session record (device id, platform, name, last-seen, push registration, identity key) backs an in-app device list where revoking a device kills its session, refresh family, and push registration at once.
TOTP is optional 2FA, recommended for admins; passkeys later.

## Invite model and Apple guidelines

Self-hosted account creation needs no email, per the brief.
An invite is a server-signed grant to create accounts, holding a hashed code, creator, max uses, use count, expiry, and role grant.
The invite link carries a 128-bit unguessable token plus the server address and identity-key fingerprint, so the joining client auto-configures and pins the right server.
Human-typeable short codes are supported only with strict per-IP and per-invite throttling and short expiry, since they carry less entropy.
Apple evaluation: the model does not conflict with App Store guidelines in principle (Mastodon and Matrix clients ship this way), and because accounts are first-party, Sign in with Apple is not triggered.
To pass review the client must still ship in-app reporting of messages and users (Guideline 1.2), user blocking, an acceptable-use agreement at signup, in-app account deletion (Guideline 5.1.1), and a 17+ age rating for user-generated content.

## Permission model foundations

A role-based model with a fixed, append-only set of named permission flags stored as an integer bitfield, fast to evaluate and cheap to store.
Effective permissions compute through one pure, exhaustively tested function: @everyone base, then the union of member roles, then per-channel role overrides, then per-member overrides, with deny winning and ADMINISTRATOR bypassing all checks.
Flags cover viewing, sending, managing messages, channels, and roles, kick, ban, moderate, invite, manage-server, connect, speak, screen-share, canvas-edit, and attach-files.
Every action is authorized server-side; client-side checks are UX only.
The Voice Canvas is the sharp case: every collaborative mutation must be authorized and validated server-side, since trusting client-broadcast mutations is a classic real-time-collaboration vulnerability.
Risk: override-precedence bugs cause escalation, mitigated by deny-by-default, a single evaluator, and exhaustive tests.

## Relay metadata minimization

The relay stays a dumb forwarder, seeing less than check-in-relay does today.
I flag that the brief's ask for the relay to maintain the server-to-device association adds metadata check-in-relay does not hold; keep it opaque.
Concretely, the home server encrypts the notification body to the device's push public key and hands the relay only ciphertext, a coarse kind (message, mention, call), and an opaque device handle.
On iOS a mutable-content push plus a Notification Service Extension decrypts on-device, so the relay, APNs, and FCM see only ciphertext, satisfying the brief's metadata goal while staying platform-compatible.
The relay stores opaque handles and per-server scoped revocable keys (check-in-relay's model), never usernames, tokens, or payloads, and logs only counts and status codes.
Residual risk: the operator can still infer activity timing (traffic analysis), accepted for v1 with batching and jitter as future work.

## Abuse and rate limiting

Layered token-bucket limits, in-process for small servers (zero external dependency, matching the lightweight target) and pluggable to Redis for the official deployment.
Relay: per-IP registration limits, per-key send limits, and a per-device wake cap to stop push-bombing.
Server: strict per-IP and per-account login throttling with backoff and lockout, invite-redemption throttling, per-user message limits, per-channel slow mode, connection caps, and canvas mutation and object caps.
Account creation is bounded by invite max-uses plus a per-IP cap; no CAPTCHA, which is heavy and privacy-hostile.
User block, server ban, and a moderator report queue serve both abuse control and Apple's requirements.

## Attachment safety

Validate by magic bytes, not extension or client Content-Type, and enforce a per-file cap (default 25 MB), per-user quotas, and a per-server storage ceiling.
Store blobs under server-generated random keys outside any web root, served with Content-Disposition attachment, nosniff, and a strict CSP so stored XSS via SVG or HTML cannot fire inline, and encrypt them at rest so leaked storage is inert.
Strip image metadata (EXIF GPS), cap pixel dimensions against decompression bombs, and decode in a resource-limited path, since image libraries are a live CVE surface (libwebp CVE-2023-4863).
Server-side link unfurling is disabled by default to avoid SSRF; if enabled it must block private and metadata IP ranges and refuse redirects.
CSAM scanning is an official-instance legal obligation and out of scope for self-hosters, flagged for the operator.

## Supply chain and dependency policy

Recommend Go for the server and relay (single static CGO-free binary, distroless nonroot, tiny footprint), a strategy-level call to confirm.
Minimal dependencies, committed lockfiles, and pinned versions, with CI gating on govulncheck and OSV-Scanner for the server and audited pub packages for the Flutter client, whose native plugins (notably flutter-webrtc) get extra scrutiny.
Every release publishes a CycloneDX SBOM and cosign-signed GHCR images with SLSA build provenance via GitHub Actions OIDC.
GitHub Actions are pinned by commit SHA, reflecting 2025 action-supply-chain compromises, and CI runs gitleaks with least-privilege tokens.
Official Firebase and APNs credentials live only on the relay; the Flutter app embeds no high-value secret, and the runtime is non-root with a read-only filesystem, dropped capabilities, and no shell.
