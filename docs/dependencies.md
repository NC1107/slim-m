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

### `package_info_plus` was held at 9.x, and is not any more

Kept here because the reason is not obvious and the trap can recur.

9.x was held because 10.x moves to `win32` 6, while every other Windows-only package in the tree sat on `win32` 5: `device_info_plus` (which `livekit_client` pulls in), `flutter_secure_storage_windows`, and `win32_registry`.
The non-obvious part is that this was never a Windows-only concern: those libraries type-check on a Linux build even though none of their code ever runs there, so a `win32` major mismatch is a hard build failure on every platform.

`file_picker` 12 needs `win32` 6, so the whole tree moved rather than the hold being lifted on its own merits.
That is also why `device_info_plus` now carries a `dependency_overrides` entry: `livekit_client` 2.8.1 pins `^12.3.0`, and forcing 13.x is what lets `win32` 6 resolve.
That override was checked rather than assumed - see the pull request that introduced it - but it is the thing to look at first if voice starts misbehaving on a client build.

If a future conflict looks like this again, the wrong move is still to bump the other `win32` packages: they follow `livekit_client`, not preference.

### `audioplayers`, for the notification chimes

The client had no audio-playback dependency at all before the notification-sound slice (Phase 8): `assets/audio/` held seven synthesised WAVs and nothing played them.

Three real candidates, checked rather than assumed.
`just_audio` has no native Linux desktop support at all (would need the separately-maintained `just_audio_mpv`), which fails this project's own bar: Fedora KDE Plasma Wayland is where the client is validated day to day, not a release-only target.
`soundpool` has no Linux plugin either (android, ios, web, macos only, per its own pubspec), same failure for the same reason.
`flutter_soloud` covers Linux, but through a bundled native C++ library compiled via FFI - exactly the shape (a bundled native capturer, not a system library) that this project's own screen-share segfault-on-Wayland trap came from, and a newer, smaller-audience package than the alternative.

`audioplayers` (github.com/bluefireteam, published under `blue-fire.xyz`, a verified pub.dev publisher) is cross-platform including Linux desktop through `audioplayers_linux`, which wraps GStreamer - a system library already present rather than something newly compiled into the app, the same shape flutter_webrtc's own Linux plugin already uses safely in this codebase.
It is also the one of the three that exposes the iOS audio session category directly (`AudioContextIOS`), which is what lets a chime ask for `.ambient` rather than interrupting or ducking whatever else is playing - see `client/packages/app/lib/src/audio/notification_sound.dart`'s own doc comment for why `.ambient` specifically, and why `mixWithOthers` must *not* be set alongside it (`AudioContextIOS`'s own asserts refuse that combination; the category already implies it).
On Android it is configured to request no audio focus at all (`AndroidAudioFocus.none`), so a chime can never be the reason a call's audio pauses or ducks.

A single `AudioPlayer` instance handles every chime (`AudioPlayersSoundPlayer`), stopped and restarted on each `play()` call rather than pooled, since overlap is rare and briefly cutting one chime short for the next is not a defect worth the complexity of a pool.
Playback goes through a `SoundPlayer` seam so a test never touches a real audio device; see `notification_sound_message_test.dart`, `notification_sound_roster_test.dart` and `notification_sound_call_ring_test.dart` for the fakes.
