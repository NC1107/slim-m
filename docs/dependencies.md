# Dependency rationale

Why the dependencies are the ones they are, and why their feature sets are cut the way they are.
Most of this file is the Rust server; the client section at the end covers `pubspec.yaml` holds that are not self-explanatory.

Neither a `Cargo.toml` nor a `pubspec.yaml` has a doc-comment mechanism and a plain comment in one is capped at two lines, so anything longer lives in this file and the manifest keeps a short note pointing at it.
Library-level decisions taken during the validation pass are in [decisions/0003-library-decisions.md](decisions/0003-library-decisions.md); this file is the running detail for the manifests themselves.

Shared versions live in the workspace `Cargo.toml` so every crate stays in lockstep.

## Auth primitives

`argon2`, `sha2` and `base64` are all long-established audited crates from the RustCrypto and BurntSushi families, not fresh single-maintainer projects.
They cover Argon2id password hashing, SHA-256 token hashing, and URL-safe base64 for the opaque token secrets.

`rand_core`'s `getrandom` feature turns on its OS entropy source (`OsRng`), which both the Argon2 salt and the opaque token secrets draw from.
This is the same `rand_core` that argon2's `password-hash` uses, so the feature simply unifies onto it.

## hmac

HMAC-SHA256 for the LiveKit access tokens, which are HS256 JWTs.
They are only ever signed here, never verified, so none of the JWT verification pitfalls (`alg=none`, algorithm confusion) are in play, and a full JWT library would be carrying parsing code this never runs.
It is the same RustCrypto family as `sha2`, and was already in the tree transitively.

## crypto_box

Anonymous sealed boxes (libsodium `crypto_box_seal`, X25519 plus XSalsa20Poly1305) for the content-free push envelope.
It is a pre-release because the `seal` API this needs has not had a 0.10 stable cut yet.
It is pinned to an exact version rather than a range, so a new pre-release cannot silently change behaviour underfoot.

## reqwest

The push relay HTTP client.
`rustls-tls` rather than the default `native-tls`, so the static musl release binary and the distroless image never need OpenSSL.
Its ring crypto provider needs only a C compiler, not cmake, so it fits the existing Alpine builder unchanged.

`url` is already pulled in transitively by reqwest.
It is named explicitly so the push relay URL's scheme and host can be validated at startup without hand-rolled parsing.

## ed25519-dalek

The server's long-lived identity keypair, behind the trust-on-first-use fingerprint.

Features are cut to `zeroize` only: no `std`, no `rand_core`, no `fast` (precomputed tables).
Nothing here signs anything yet, and deriving the keypair then storing the public half at boot is the only operation this crate performs.

It is held at 2.x rather than the freshly cut 3.0.0.
3.0.0 depends on curve25519-dalek's stable 5.0.0, which cargo cannot resolve alongside `crypto_box`'s pinned 5.0.0-pre.1 in the same tree, because a pre-release satisfies nothing outside its own pre-release line.

## The release profile

`opt-level = "z"`, LTO, one codegen unit, stripped, and `panic = "abort"`.
The brief treats binary size as a budget for a self-host binary, and `server-ci` enforces it at 20 MiB.

## Dev dependencies

`tower`'s `ServiceExt::oneshot` drives the HTTP round-trip tests in-process without binding a socket.
`tokio-tungstenite` is a real WebSocket client for the two-client fan-out test.

`jsonschema` backs `tests/response_contract.rs`, which validates real responses against `schema/openapi.yaml`.
An OpenAPI 3.1 schema object *is* a JSON Schema 2020-12 schema, so a general JSON Schema validator checks it directly, rather than a hand-written copy of each shape drifting alongside the real one.
`default-features = false` drops the file and http `$ref` resolvers, and the reqwest and aws-lc-rs they drag in: every `$ref` in that document is a local pointer into the one document.

`serde_yaml_ng` is the maintained fork of the archived `serde_yaml`, used only to turn the schema into a `serde_json::Value` the validator can compile.

## Client holds

### `package_info_plus` is held at 9.x

10.x moves to `win32` 6, and every other Windows-only package in the tree is still on `win32` 5: `device_info_plus` (which `livekit_client` pulls in), `flutter_secure_storage_windows`, and `win32_registry`.

The non-obvious part, and the reason this is not a Windows-only concern: those libraries type-check on a Linux build even though none of their code ever runs there.
A `win32` major-version mismatch is therefore a hard build failure on every platform, not a problem you discover when you first build for Windows.

What the hold buys is current `livekit_client` and `flutter_webrtc`.
That is the constraint to weigh against, so resolving this by bumping the other `win32` packages is the wrong move: they are pinned by what `livekit_client` depends on, not by preference.
