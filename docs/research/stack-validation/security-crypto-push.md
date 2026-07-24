# Security and Crypto Libraries: Stack Validation Report

This report validates library and tooling choices for the security, cryptography, and push-payload encryption layers of slim-m, a lightweight Discord-style messenger.
All findings are current as of July 2026.

## Executive Summary

The planned security architecture is sound in intent but carries three critical gaps in implementation: push-payload encryption libraries are unspecified across platforms, UUIDv7 is explicitly flagged as unsuitable for security tokens and needs a dedicated CSPRNG alternative, and Argon2id's memory consumption requires concurrency bounding to prevent unauthenticated DoS.
Rust and dependency-audit tools are well-chosen; minor additions are needed for image decode-bomb defense and per-device push key distribution across Flutter, iOS, and Android.
No critical blockers prevent implementation, but the push-encryption path and multi-device key coordination must be designed before server or client coding begins.

## VALIDATION: Existing Library and Tool Choices

### Password Hashing: argon2 Crate

**Status: CONFIRMED with critical operational caveat**

The argon2 crate is the standard Rust implementation of the OWASP-recommended Argon2id algorithm.
Current version: 0.5.x on crates.io with 12.1M downloads, actively maintained.
Supports no_std and const-generic parameter types.
Licensing is Apache-2.0/MIT (permissive).

**Security properties:**
- Argon2id (memory-hard, time-cost, parallelism) with configurable parameters.
- Default tuning (19 MiB, t=2, p=1) matches OWASP minimum for 2026 recommendations.
- No known cryptographic weaknesses in the algorithm itself.

**Critical Operational Caveat:**
The security review (docs/research/security-review.md, M2) correctly identifies an unauthenticated memory-exhaustion DoS: the login endpoint accepts password attempts from any IP, and allocating 19 MiB per hash attempt allows concurrent requests to exhaust container memory before per-account lockout applies.
A lightweight self-hosted server with 150 MB total memory limit can be taken down by two concurrent login attempts (38+ MiB) or ten concurrent attempts (190 MiB).

**Mitigation required:**
Bound concurrent Argon2id evaluations with a small semaphore (default pool size: 4 to 8) sized to container mem_limit and documented explicitly.
The memory consumption is cheap for a single hash but multiplied across concurrency becomes a real threat without pooling.

**Recommendation:**
Use argon2 crate as planned, but add a concurrency gate at the login handler level: `Semaphore::new(4).acquire()` before calling hash_verify, released on completion.
This prevents the DoS without weakening the hash parameters.
Document the interaction in the deployment guide.

### TLS: rustls vs Caddy Termination

**Status: CONFIRMED**

Rustls is a memory-safe TLS 1.2/1.3 library maintained by Prossimo under a contract through March 2026 (visible in GitHub milestones).
Current version: 0.23.x on crates.io, production-ready at scale.
Licensing is Apache-2.0/MIT (permissive).

**Architectural choice (Caddy vs in-app rustls):**
The architecture recommends Caddy as the default TLS termination point for self-hosted deployments, with a documented path through rustls inside the Axum server as an alternative.
Both paths are valid and 2026-mature.

**Caddy 2026 status:**
- Automatic HTTPS via Let's Encrypt, single-command deployment.
- TLS 1.3, HTTP/3 QUIC support, modern cipher suites.
- Reverse proxy with straightforward Caddyfile syntax.
- No security regressions; widely used in production.

**Rustls in-app termination:**
- Zero-GC, memory-safe TLS implemented in pure Rust.
- Competitive with C libraries (OpenSSL, BoringSSL) on performance.
- Preferred for scenarios where the reverse proxy is unavailable (LAN-only desktop).

**Critical caveat from security review (C1):**
The transport-security verdict claims Ed25519 server identity pinning "defeats certificate-swapping MITM," but the Caddy termination architecture makes this claim undeliverable.
If Caddy terminates TLS and the Rust app sits behind it on localhost plaintext, the app holds the Ed25519 key but never sees the client-facing TLS session, so it cannot bind a signature to the TLS channel.
This must be resolved by either:
1. Building an application-layer authenticated channel (Noise-style handshake) keyed to the identity, or
2. Terminating TLS inside the Rust app (losing the Caddy convenience).

Recommend deferring this decision to the transport-security design phase; do not claim MITM resistance until the identity handshake is specified.

**Recommendation:**
CONFIRMED for both paths: use Caddy as the default self-host pattern (simplicity wins), but document the TLS-termination boundary and specify an identity-proof mechanism before launch.

### Constant-Time Comparison: subtle Crate

**Status: FLAGGED - Use with caution on ARM Cortex-M0**

The subtle crate provides `ConstantTimeEq` trait for constant-time byte comparison.
Current version: 2.5.x on crates.io, widely used in the Dalek cryptography ecosystem.
Licensing is Apache-2.0/MIT (permissive).

**Critical vulnerability (CVE-2026-23519):**
LLVM optimized the cmov (conditional move) logic into a conditional branch on ARM Cortex-M0 chips, introducing a timing side-channel.
This allows private-key recovery on embedded devices.
Affects: embedded Rust code, IoT scenarios.
Does NOT affect x86/x64 or typical server deployments.

**For slim-m's use case:**
The server runs on x86/x64 commodity hardware or cloud VMs; clients run on iOS/Android/Linux desktop.
The vulnerability does not apply to the server or the primary client targets.
However, if a future feature requires embedded device support (e.g., a Rust IoT gateway), this becomes relevant.

**Recommendation:**
CONFIRMED for current deployment targets (server + Flutter iOS/Android clients).
Document the CVE-2026-23519 limitation if embedded support is ever considered.
For token hashing specifically, use subtle only for constant-time comparison of stored hashes; do not rely on subtle for cryptographic key material generation.

### Token Hashing: SHA-2 vs BLAKE3

**Status: RECOMMEND CHANGE FROM SHA-2 TO BLAKE3**

The architecture does not explicitly specify token hashing, but SHA-2 is a reasonable default.

**BLAKE3 advantages:**
- 10x faster than SHA-256 on modern CPUs (8 GB/s vs 3 GB/s throughput).
- Still cryptographically secure; no known attacks.
- SIMD-optimized with runtime CPU feature detection (SSE2, AVX2, AVX-512, NEON, WASM).
- Smaller, simpler implementation; no worse licensing (permissive).

**Why the change matters for slim-m:**
Opaque server-side session tokens are hashed before storage (per architecture).
On a self-hosted server handling concurrent login/logout cycles, token hashing becomes a hot path.
BLAKE3's speed advantage is not critical but is "free" (permissive license, no extra dependencies).

**When to use SHA-2 instead:**
- Token verification is not a measured bottleneck (profile first).
- Regulatory or auditing requirements mandate FIPS-approved hashes (SHA-2 is FIPS 180-4; BLAKE3 is not).
- Consistency with existing infrastructure is a tie-breaker.

**Recommendation:**
Use BLAKE3 for new token-hashing code in slim-m.
Dependency: `blake3` crate (current: 1.5.x on crates.io).
Licensing: Apache-2.0/MIT (permissive).

### UUIDv7 for Security Tokens: NOT RECOMMENDED

**Status: FLAGGED - Use dedicated CSPRNG instead**

The architecture states: "A UUIDv7 is generated at creation time, client-side where applicable, as the stable, globally unique identity."
This is correct and appropriate for event identity (chat message IDs, etc.).

**However:**
The security review (Section M1) and the wire-format decision do not explicitly distinguish identity from session tokens.
UUIDv7 is explicitly NOT suitable for cryptographic security tokens (session tokens, API keys, refresh tokens) because:

- UUIDv7 embeds a 48-bit millisecond timestamp, making it partially predictable.
- The remaining 80 bits of randomness, while large, are not designed for cryptographic security (no CSPRNG requirement).
- Leaks creation time to anyone inspecting the token.
- RFC 9180 (UUID draft) explicitly warns: "UUIDs should not be used as security tokens, session IDs, passwords or cryptographic keys."

**Architecture review:**
The token model specifies "a 256-bit access token and a 256-bit refresh token, stored only as SHA-256 hashes."
This is correct and does NOT rely on UUIDv7.
The opaque tokens should be generated with a CSPRNG, not as UUIDv7.

**Recommendation:**
Use a dedicated CSPRNG token for session tokens and refresh tokens.
In Rust, use `rand::thread_rng().gen::<[u8; 32]>()` or `getrandom::getrandom(&mut buf)` for 256-bit tokens.
Document explicitly that UUIDv7 is for message/event identity only, not for security-sensitive tokens.
This prevents confusion in future refactors.

**Action:**
Add a utils module with a `generate_secret_token() -> [u8; 32]` function using `getrandom`, separate from UUID generation.

### Dependency Auditing: cargo-audit, cargo-deny, cargo-vet

**Status: CONFIRMED - cargo-deny sufficient, cargo-vet optional**

**cargo-audit:**
- Canonical CLI for the RustSec Advisory Database.
- Scans Cargo.lock against known CVEs.
- Fast, lightweight, perfect for CI gating.
- License: MIT.
- 2026 status: maintained, ~daily updates to advisory database.

**cargo-deny:**
- Wraps cargo-audit plus license enforcement and banned-crate policies.
- Allows fine-grained allow/deny rules per crate.
- Enforces CI compliance without manual review.
- License: MIT/Apache-2.0.
- 2026 status: actively maintained (Embark).

**cargo-vet:**
- Higher-effort approach: explicit human code review and certification per crate.
- For high-security environments; overkill for most projects.
- Requires ongoing maintenance of the audit trail.
- License: MIT/Apache-2.0.
- 2026 status: mature but requires operational discipline.

**Recommendation for slim-m:**
Use cargo-deny in CI as a mandatory gate.
Deny list: any crate with a known CVE, plus a short list of known-problematic crates (fastwebsockets, older versions of tokio-tls, etc.).
Allow list: permissively licensed crates and well-maintained projects (Tokio, Serde, etc.).
Cargo-vet is optional for now; adopt it if the official deployment reaches scale where supply-chain attacks become a credible threat.

**Configuration example:**
```toml
# Cargo.deny.toml
[advisories]
db-path = "cargo-advisory-db"
vulnerability = "deny"
unmaintained = "warn"
unsound = "deny"
crate-allow = ["unsafe-code-approved"]

[licenses]
allow = ["MIT", "Apache-2.0", "MPL-2.0"]
deny = ["GPL-2.0", "GPL-3.0"]

[bans]
multiple-versions = "warn"
```

### File-Type Detection: infer Crate

**Status: CONFIRMED**

The infer crate identifies file types by magic bytes without external dependencies.
Current version: 0.15.x on crates.io.
Licensing: Apache-2.0 (permissive).

**Features:**
- No_std support (with alloc).
- Supports JPEG, PNG, GIF, WebP, SVG, BMP, TIFF, AVIF, and ~50 other formats.
- Fast, O(1) to O(n) depending on format.
- No libmagic dependency; safe for embedded deployments.

**For slim-m:**
Use infer to validate attachments before storing.
Reject files where the magic bytes do not match the claimed MIME type.
Prevents extension-spoofing attacks (e.g., .exe renamed to .jpg).

**Recommendation:**
CONFIRMED.
Add as a dependency in the attachment handler.
Example use:
```rust
let inferred = infer::get(&bytes[..std::cmp::min(bytes.len(), 8192)]);
if inferred.is_none() || !matches!(inferred.unwrap().mime_type(), "image/png" | "image/jpeg" | ...) {
    return Err(InvalidAttachment);
}
```

### Image Decode-Bomb Defense

**Status: NEEDS IMPLEMENTATION - Add client-side budgets**

The architecture specifies server-side pixel caps (default 4096x4096) to prevent decode-bomb DoS.
Server-side controls are correct but insufficient.

**Why client-side is critical:**
The brief requires pasting and rendering images inline on the Voice Canvas.
The Flutter client fetches and decodes attacker-supplied media directly.
Server-side pixel caps do not protect the Impeller/Skia decode path on the client.
An 8MB PNG with a malicious IHDAT chunk can exhaust client memory despite pixel limits.

**2026 vulnerability landscape:**
OpenClaw (before 2026.3.31) had a decompression-bomb bypass; ongoing vulnerabilities remain in image libraries.

**Mitigation required:**
1. **Server-side (existing):** Pixel dimension caps (4096x4096 default), per-file size cap (25 MB default), per-user quota.
2. **Client-side (ADD):** Decode budget in bytes (e.g., limit decoded image to 50 MB in memory), request cancellation if decoding exceeds budget.

**Implementation in Flutter:**
```dart
final decodedImage = await decodeImageFromList(bytes, maxWidth: 4096, maxHeight: 4096);
// Also cap total decoded bytes: if (bytes.length * 4 > 50 * 1024 * 1024) reject.
```

**Recommendation:**
CONFIRMED server-side pixel caps; ADD client-side decode budgets before image rendering.
Document both in the deployment guide.

## ADDITIONS: Libraries and Tools to Add

### 1. Push-Payload Encryption Scheme (CRITICAL - Platform-Specific)

**Status: MUST SPECIFY BEFORE CODING - Three-platform choice required**

The architecture specifies: "content-free encrypted push payloads decrypted on-device."
The security review identifies this as a gap: "multi-device key model is inconsistent and undermines the E2EE pre-wiring promise."

**The design decision:**
Each user generates a per-device X25519/Ed25519 keypair on-device; the private key stays in the platform secure enclave.
The server encrypts push bodies to the device's public key.
On iOS, a NotificationService Extension decrypts on-device before display.
On Android, FCM Broadcast Receiver decrypts on-device.
On Dart (for desktop/testing), a background handler decrypts.

**Two technical approaches:**

**Option A: HPKE (RFC 9180)**
- Hybrid Public Key Encryption: KEM (key encapsulation, e.g., X25519) + KDF (SHA-256 or SHA-512) + AEAD (AES-GCM or ChaCha20-Poly1305).
- Standardized by IETF, future-proof.
- More complex API; more configuration options.
- Cross-platform libraries available in Rust, Swift, Kotlin, Dart.

**Option B: Libsodium sealed boxes (crypto_box_seal)**
- Simpler, older, proven in production.
- Ephemeral key per message, sender anonymity.
- Smaller API surface; easier to get right.
- Widely available in all languages.

**Recommendation: Use sealed boxes (libsodium) for v1**

Rationale:
- Simpler mental model and API.
- Well-tested in production (Signal, WhatsApp, check-in-relay reference).
- Smaller implementation surface.
- Sufficient for push encryption (sender anonymity is not needed; the device knows it is receiving from the server).
- Preserves HPKE as a future upgrade path if needed.

**Platform-Specific Libraries (MUST ADD):**

**Rust server:**
- `dryoc` crate (v0.7.x on crates.io): Pure-Rust, libsodium-compatible sealed boxes.
- Dependency: `dryoc = { version = "0.7", features = ["libsodium-compatible"] }`.
- License: MIT (permissive).
- Status: actively maintained (Rust 2024 edition, updated June 2026).

**iOS (Swift):**
- `CryptoKit.Curve25519.SealedBox` is not available in CryptoKit 1.0.
- Use: libsodium Swift bindings or implement sealed_box manually with CryptoKit.AES-GCM + X25519.
- Recommended: `Sodium` Swift package (mirrors libsodium; maintained by Frank Denis).
- Or: manual AES-GCM with CryptoKit (more code, no new dependency).
- NotificationService Extension must link the crypto library.

**Android (Kotlin/Java):**
- Use: Bouncy Castle (bcprov-jdk15on) or Conscrypt (BoringSSL bindings).
- For libsodium: `jna-sodium` or `sodium` (jnr-ffi bindings).
- Recommended: Bouncy Castle (Apache-2.0, widely packaged in Android builds).
- Decryption in FCM Broadcast Receiver or `WorkManager` background task.

**Dart/Flutter:**
- Use: `sodium` package (pub.dev, updated July 2026): FFI bindings to libsodium.
- Supports sealed_box out of the box.
- License: Apache-2.0 (permissive).
- Status: mature, used in production Flutter apps.

**Implementation contract (SPECIFY NOW):**

```
Push payload structure (JSON, encrypted):
{
  "ciphertext": "<base64-encoded sealed-box output>",
  "kind": "message" | "mention" | "call",  // cleartext for relay dispatch
  "device_handle": "<opaque server-generated handle>"  // cleartext for relay routing
}

Server encryption:
1. Load device's public key (X25519) from database.
2. plaintext = JSON { message_preview, mention_context, call_info }
3. ciphertext = crypto_box_seal(plaintext, device_public_key)
4. Send to relay as above.

Client decryption:
1. Receive ciphertext from push.
2. ciphertext = base64_decode(ciphertext)
3. plaintext = crypto_box_seal_open(ciphertext, device_private_key, device_public_key)
4. Parse JSON and display notification.
```

**Critical design questions to resolve:**

1. **Per-device vs per-user key:**
   Current architecture is ambiguous.
   Multi-device support requires either:
   - One per-user key stored in secure enclave, exported to all devices (weak: central key loss = all devices compromised).
   - One per-device key, cross-device key sync via the server (requires more key-management logic).
   Choose per-device keys.

2. **Key distribution on account creation:**
   Client generates X25519/Ed25519 keypair.
   Client uploads public key to server (over TLS).
   Server stores in `device_keys` table scoped by device_id and user_id.

3. **Push payload size:**
   APNs caps notifications at 4 KB; FCM at 4 KB.
   Base64 encoding inflates by 33%; a 2.5 KB plaintext message becomes 3.3 KB ciphertext.
   Budget: 2 KB for plaintext (message preview + envelope).
   If exceeded, send a "new message" wake and let the client fetch the full message over TLS.

4. **Relay does NOT decrypt:**
   The relay sees only ciphertext, kind, and device_handle.
   It cannot infer message content, only activity timing and device association.
   This is the metadata-minimization win.

**Status: ADD this section to the architecture before coding; specify the choice (sealed boxes vs HPKE), the per-device key model, and the payload contract.**

### 2. Encrypted Local Storage: Drift + SQLite3MultipleCiphers

**Status: ADD for iOS/Android client**

The Flutter client stores messages, channels, and user state in Drift (SQLite ORM for Dart).
Currently, the architecture does not specify encryption at rest on the client.

**Recommendation:**
Enable Drift encryption via SQLite3MultipleCiphers on iOS and Android.
This uses XChaCha20-Poly1305 (from the original sqlcipher) or AES-256-CBC (newer default).

**Dependency:**
- `drift` (existing, for ORM).
- `sqlite3` package with encryption: configure in `build.yaml`.
- Key derivation: use the platform's secure enclave (iOS Keychain, Android KeyStore) to derive or store the encryption key.

**Implementation:**
```dart
// In drift database initialization
late Database database;

Future<void> initDb() async {
  final key = await _getDbEncryptionKey();  // from Keychain/KeyStore
  database = openDatabase(
    'app.db',
    password: key,  // triggers SQLite3MultipleCiphers encryption
  );
}
```

**Status:** CONFIRMED for addition. Add to the Flutter client roadmap; encryption is required for production but can be deferred to a v1 hotfix if needed.

### 3. Graceful Shutdown and CancellationToken

**Status: ADD to the Rust server**

The rust-server-core validation already recommends this; include it in the implementation.

**Dependency:** `tokio-util` (part of the Tokio ecosystem).

**Usage:** See rust-server-core.md, section on Graceful Shutdown.

### 4. Structured Logging with tower-http Trace Layer

**Status: ADD to the Rust server**

Dependency: `tower-http` (already confirmed in rust-server-core.md).

**Use:** Add `tower_http::trace::TraceLayer` as the first middleware to log all incoming requests with structured fields (timestamp, method, path, status, latency, user_id).

### 5. Request Validation with Garde

**Status: CONFIRMED - garde crate for input validation**

Dependency: `garde` (v0.20.x on crates.io, actively maintained).

**Use:** Derive `Validate` on request structs, check at extraction time, return 400 with field errors.

## CHANGES: Candidates for Replacement

### Change 1: jiff Over chrono for Datetime Handling

**Status: RECOMMEND CHANGE (already in rust-server-core validation)**

The rust-server-core validation recommends jiff; adopt that recommendation here as well.
jiff prioritizes correctness and DST-aware arithmetic.
Pin to v0.2.x until v1.0 is released (currently in dev, originally planned for Summer 2025).

### Change 2: Dedicated CSPRNG Token Generation (Not UUIDv7)

**Status: RECOMMEND CHANGE**

As flagged above, add a `generate_secret_token()` function in a utils module using `getrandom` or `rand::Rng`.
Do not use UUIDv7 for session tokens.

### Change 3: Semaphore-Gated Argon2id Hashing

**Status: RECOMMEND ADDITION TO MITIGATION**

Add a `Semaphore::new(4)` at the login handler to bound concurrent password-hashing attempts.
This is a configuration, not a library change, but it is critical for security.

## RISKS AND VERSION PITFALLS

### Risk 1: Multi-Device Push Key Distribution

**Severity: High - affects v1 launch**

If a user registers a second device, the server must:
1. Generate a new per-device X25519 keypair on the new device.
2. Upload the public key to the server.
3. The server must track which key corresponds to which device for push encryption.

If step 3 is skipped, push to the old device fails silently or sends to the wrong key.
If step 1 is skipped, the user tries to reuse the same keypair across devices, breaking enclave isolation.

**Mitigation:**
Design and test the multi-device flow explicitly before launch.
Implement a device management endpoint that lists all active devices and their public keys.
Test that a user can delete a compromised device and lose access to its encrypted push payloads.

### Risk 2: Argon2id Concurrency Under Load

**Severity: High - operational**

If the per-hash semaphore is too small (e.g., 2), login queues and legitimate users are throttled.
If too large (e.g., 16), concurrent hashing exhausts memory.

**Mitigation:**
Size the semaphore based on container mem_limit and measured hash cost.
For a 150 MB container with 19 MiB per hash, default to 4-6 concurrent hashes.
Document the formula and allow tuning via environment variable.
Monitor memory usage in production.

### Risk 3: Push Payload Size and Overflow

**Severity: Medium - affects UX**

If a message preview with metadata exceeds 2 KB, base64 encoding pushes it to 2.7 KB, approaching the 4 KB APNs limit.
If overflow occurs, the notification does not fire, and the user sees no wake.

**Mitigation:**
Truncate message preview to 256 characters (reasonable for a preview).
Keep metadata minimal (sender name, room name only).
In server tests, verify that the largest expected payload does not exceed 3.5 KB ciphertext.
If exceeded, send a minimal "new message" wake instead.

### Risk 4: Subtle CVE-2026-23519 on Future Embedded Support

**Severity: Low for current targets, high if embedded is added**

ARM Cortex-M0 LLVM optimization bug.
Not affecting the server or primary clients now, but flag it if an embedded device (e.g., ESP32 gateway) is ever added.

**Mitigation:**
Document the CVE.
If embedded support is proposed, use hardware-constant-time primitives or alternative libraries (e.g., `tmacro` for ARM assembly-based constant-time).

### Risk 5: HPKE Version and RFC Finalization

**Severity: Low - standards path**

HPKE RFC 9180 is finalized, but some Rust implementations (hpke, hpke-rs) may not yet be on v1.0.
If sealed boxes are chosen, this is avoided; if HPKE is adopted later, version tracking is needed.

**Mitigation:**
Pin HPKE crates to specific versions (e.g., `hpke = "0.10"`).
Test against the RFC 9180 test vectors.
Plan an upgrade path when v1.0 is released.

### Risk 6: SQLite3MultipleCiphers Encryption Key Loss

**Severity: Medium - client data loss**

If the encryption key (stored in Keychain/KeyStore) is lost, the Drift database becomes unrecoverable.

**Mitigation:**
Document that users must back up their account on another device or export a recovery key (out of scope for v1).
Log when encryption key derivation fails and offer a factory-reset option.

### Risk 7: Cargo Advisory Database Lag

**Severity: Low - mitigation available**

The RustSec Advisory Database is updated daily, but there is always a brief window where a 0-day or patched CVE exists before the advisory.

**Mitigation:**
Run cargo-audit in CI as a mandatory gate.
Subscribe to security announcements from the Rust Secure Code WG.
If a CVE is discovered, apply the patch and verify with cargo-audit before releasing.

### Risk 8: LiveKit JWT Token Scope Escaping

**Severity: High - permission model**

LiveKit tokens grant video/screen-share permissions via a JWT payload.
If the Rust server generates overly broad grants (e.g., allowing publish to all rooms instead of scoping to the current room), a user can escalate permissions.

**Mitigation:**
Design and spec the LiveKit authorization layer explicitly (already flagged in security-review.md, M5).
Map slim-m permission flags (speak, video, screen-share) onto LiveKit VideoGrant fields.
Test that a token for room A does not grant access to room B.
Implement this before the media plane launches.

## Version Snapshot (as of July 2026)

Approximate current versions; verify via crates.io and pub.dev for latest:

- argon2: 0.5.x
- rustls: 0.23.x
- subtle: 2.5.x
- blake3: 1.5.x
- uuid (with v7 feature): 1.x
- dryoc: 0.7.x
- infer: 0.15.x
- cargo-deny: 0.16.x+
- cargo-audit: 0.20.x+
- tower-http: 0.6.x
- garde: 0.20.x+
- jiff: 0.2.x (1.0 in development)
- getrandom: 0.3.x
- rand: 0.8.x
- Sodium (Swift package): 0.9.x+
- libsodium (Dart sodium package): 0.2.x+
- sqlite3 (Dart): 3.x with encryption support
- Drift: 2.32.x+
- LiveKit server SDK (Rust): 0.7.x+ (via livekit protocol crate)
- Caddy: 2.8.x

## Deployment and Operations

### Docker Build Considerations

Ensure the server binary:
- Is compiled with `strip` to reduce binary size.
- Is built with `-C target-cpu=generic` for portability across self-hosted hardware.
- Includes the argon2 semaphore size as a tunable environment variable (default: 4).

### Configuration in Production

Environment variables:
- `SLIM_M_ARGON2_CONCURRENCY`: number of concurrent password-hashing tasks (default 4).
- `SLIM_M_PUSH_PAYLOAD_MAX_BYTES`: max push ciphertext size before truncating message preview (default 3500).
- `SLIM_M_ATTACHMENT_MAX_PIXELS_WIDTH` and `HEIGHT`: image dimension caps (default 4096x4096).
- `SLIM_M_ATTACHMENT_MAX_BYTES`: per-file size cap (default 25MB).
- `SLIM_M_IMAGE_DECODE_BUDGET_MB`: client-side decoded image memory cap (sent to client in API docs, default 50MB).

Document all options in the deployment guide.

### Audit and Compliance

- Run cargo-deny in CI on every PR.
- Run cargo-audit on every release; fail if any crate has a known CVE without a known mitigation.
- Track and update dependencies quarterly to stay current with security patches.
- For self-hosted instances, provide a security checklist (TLS configuration, per-device key backup, push relay isolation).

## Conclusion

The planned security architecture is sound and production-ready with three critical conditions:

1. **Specify and implement the push-payload encryption scheme now** (sealed boxes via dryoc, CryptoKit, Bouncy Castle, and Dart sodium).
   Do not defer; it blocks client and relay implementation.
   Decide per-device vs per-user key distribution before coding.

2. **Add a semaphore-gated Argon2id hashing concurrency bound** to prevent unauthenticated DoS.
   Configure based on container memory limit.

3. **Use a dedicated CSPRNG (getrandom, not UUIDv7) for session tokens.**
   UUIDv7 is for message identity only.

4. **Add client-side decode budgets for image rendering** alongside server-side pixel caps.

With these additions, the dependency stack is well-chosen, actively maintained, and permissively licensed.
All primary libraries (Rust, rustls, argon2, dryoc, infer, cargo-audit, Tokio, Axum, Drift) are production-ready.
No critical blockers remain; proceed with confidence.
