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

### No charting package, for the Space analytics screen

The Space usage analytics screen (`docs/decisions/0008-space-analytics.md`) needed three small bar charts: messages by day, active hours, and a memory series.
`fl_chart` and `syncfusion_flutter_charts` were the two real candidates, and both were rejected on the same grounds this project already used for the Voice Canvas and the speaking ring: a small, bespoke drawing is a `CustomPainter`, not a dependency, and this is three bar charts, not a dashboard toolkit.
`fl_chart` alone would have pulled in real weight (its own gesture, tooltip, and legend machinery) for a screen with no gestures, no legend, and one visible series each.
`AnalyticsBarChart` (`client/packages/app/lib/src/widgets/analytics_bar_chart.dart`) is under 100 lines and is reused for all three series rather than growing a chart type per series.

### `window_manager`, `tray_manager` and `screen_retriever`, for the desktop window shell

`docs/decisions/0012-desktop-window-shell.md` designs the startup animation, close-to-tray and the frameless title bar; these three are what it recommends and why, restated here since a manifest comment is capped at two lines.

All three are published by `leanflutter.dev`, a verified pub.dev publisher, actively maintained, and none bundles a native capturer the way `flutter_soloud` did for the notification-sound slice - the shape this project's own screen-share segfault-on-Wayland trap came from and now checks for on every new native plugin.
Each wraps system APIs already linked into the app rather than compiling anything new in: GTK/GDK on Linux (`window_manager`), Win32 (both, once Windows is scaffolded), AppKit (both, once macOS is scaffolded), and `libayatana-appindicator3` for the Linux tray icon, which is why the Linux build-dependency lists in `main-builds.yml`, `client-ci.yml` and `release.yml` all gained `libayatana-appindicator3-dev` alongside this change.

`bitsdojo_window` was rejected: it solves the identical frameless/drag/resize problem `window_manager`'s own `setAsFrameless()`/`startDragging()` already solve, and this project already declines to carry two packages doing one job (one `AudioPlayer` instance rather than a pool, one bar-chart `CustomPainter` rather than a charting library, above).
`system_tray` was rejected too: an older, separately-authored `tray_manager` alternative with no reason to prefer it once `tray_manager` already shares a publisher and an idiom family with the window package this pass already chose.

Writing the window and tray plumbing from scratch was considered and rejected, on the inverse of the FFI-versus-system-library reasoning above: these three are not a bundled native capturer needing compiling, they are thin wrappers over real, already-linked system libraries, so reimplementing three platform-specific window backends plus a D-Bus tray protocol buys nothing a maintained package does not already give.
One piece stayed hand-written anyway: the Linux tray-availability probe (`linux/runner/linux_tray_probe_channel.cc`), a single `org.kde.StatusNotifierWatcher` D-Bus property read.
Pulling in a general-purpose Dart D-Bus package for one boolean is heavier than the job needs when GDBus is already linked into the app via GTK/GIO, and this project already has the identical precedent in this same directory: `clipboard_image_channel.cc`, a roughly-90-line hand-written channel bridging one narrow piece of GTK/glib functionality no package covers.

### `archive`, for bulk emoji import

Backlog #137 unzips an admin-picked `.zip` client-side and uploads one custom emoji per image inside it, one `POST /emoji` per file rather than a new server route: see `client/packages/app/lib/src/screens/admin/emoji_bulk_plan.dart`.
`archive` is the standard pure-Dart zip codec (no FFI, no bundled native decoder), already present transitively through `image` (a `livekit_client` dependency), so this adds no new supply-chain surface, only a direct declaration of a package already in the resolved tree.

### `desktop_drop`, for OS drag-and-drop

Dragging a file onto the composer, or a `.zip` onto the emoji import card, reuses the exact same staging/upload paths the existing pickers already call - see `client/packages/app/lib/src/widgets/app_drop_zone.dart`.

`desktop_drop` (MixinNetwork) was picked over `super_drag_and_drop`: this feature only ever needs "which files landed on this widget", not `super_drag_and_drop`'s own virtual-file and clipboard-reading machinery, which this app has no other use for.
Its own `pubspec.yaml` declares plugin implementations for macOS, Linux, Windows, Android and web; there is no iOS entry, so `DropTarget` mounts everywhere but only ever receives events on the platforms that generate them.
Nothing here needs a `dart.library.*` conditional import: the package is a properly federated plugin (a real web implementation registered through the normal plugin registrant, not a `dart:io` shortcut), so `flutter build web --release` links it the same way it already links `file_picker`.
`app_drop_zone.dart` still gates the target on `kIsWeb` plus a desktop `defaultTargetPlatform`, never `Platform.isX`: a platform check here is about input capability, matching `docs/design/desktop-vs-mobile.md`'s own rule that a platform check is for capability, never for shape - OS drag-and-drop is meaningless on a touch screen regardless of which OS is under it.

### `media_kit`, `media_kit_video` and `media_kit_libs_video`, for inline video playback

A `video/*` attachment used to render as an inert filename chip on every platform.
`video_player`, the Flutter-team package, was the obvious first candidate and is the wrong one for this project: its own platform list stops at Android, iOS, macOS and web, with no Linux or Windows support at all - the identical failure `just_audio` and `soundpool` had for the notification-sound slice above, and the same bar applies: Fedora KDE Plasma Wayland is where this client is validated day to day, not a release-only target.

`media_kit` covers all six shipped platforms, Linux and Windows included, and was checked rather than assumed: `flutter build linux --release` and a real widget test constructing its `Player` both ran clean on this project's own Fedora 44 development machine, against the system `mpv-libs` package already installed there (see below), which is the strongest evidence available short of a manual playback session.

Unlike `audioplayers` and `window_manager` above, this is not a thin wrapper over an already-linked system library on every platform - it is one on Linux specifically, and something else everywhere else. There are two separate paths to `libmpv`, not one, and conflating them is a trap this project's own CI hit directly: `media_kit`'s own Dart FFI layer (`native_library.dart`) resolves `libmpv` at runtime through `dart:ffi`'s `DynamicLibrary.open` to drive playback, exactly the dlopen shape this section originally described - but `media_kit_video`'s own Linux plugin (the video texture/rendering integration) does something different, and does it at build time: its `linux/CMakeLists.txt` runs `pkg_check_modules(mpv IMPORTED_TARGET mpv)` and `pkg_check_modules(epoxy IMPORTED_TARGET epoxy)`, then `target_link_libraries`s the plugin against both. `flutter build linux --release` on a plain GitHub-hosted Ubuntu runner failed on exactly this - `CMake Error ... Target "media_kit_video_plugin" links to: PkgConfig::mpv ... but the target was not found` - which a widget test on this project's own Fedora machine never caught, because that machine already has `mpv-devel` installed for unrelated reasons. Reproduced in a clean `ubuntu:24.04` container to confirm the fix: installing `libmpv-dev` and `libepoxy-dev` makes the CMake error disappear, and `readelf -d` on the resulting `libmedia_kit_video_plugin.so` shows real `NEEDED` entries for `libmpv.so.2` and `libepoxy.so.0` - not dlopen, a genuine link. `.github/actions/linux-build-deps` (the one shared composite action `client-ci.yml`, `main-builds.yml` and `release.yml` all use) now installs both.

That link has a second consequence beyond the build: Flutter's Linux embedder dlopens every registered plugin at process startup, not only when a video is actually opened, so a machine missing `libmpv.so.2` or `libepoxy.so.0` at runtime may fail to launch the app at all - not merely fail to play a video. `client-ci.yml`'s `linux desktop shell smoke` job downloads the compiled bundle and runs it under Xvfb, so it now installs the runtime packages (`libmpv2`, `libepoxy0`) alongside the other runtime libs it already named explicitly for the same reason (see that job's own comment on why the compile job's `-dev` packages do not carry over). On Android, iOS, macOS and Windows, `media_kit_libs_video` bundles a real prebuilt `libmpv` inside the plugin, the same shape `window_manager`'s wrappers use for their own platforms. On Linux, `media_kit_libs_linux` bundles nothing at all - a deliberate upstream choice ("this is how GNU/Linux works," its own README) - so both shared libraries have to already be on the machine, the same way GStreamer already has to be on the machine for `audioplayers_linux`. `packaging/rpm/slim-m-client.spec` now names the exact sonames (`libmpv.so.2` and `libepoxy.so.0`, not the unversioned `libmpv.so` the upstream docs quote, since a plain `mpv-libs` install - no `-devel` - only ships the versioned one, confirmed by installing it and checking) as explicit `Requires`, alongside the ones rpm's own ELF scan should already catch on its own now that they are real links rather than dlopen targets.

The Flatpak manifest (`packaging/flatpak/top.npcserver.slimm.yaml`) shipped this gap for a while: `org.freedesktop.Platform` carries no `libmpv`, and nothing built or vendored one the way `libayatana-appindicator3` already gets a module for the tray icon, so Flatpak installs of the client could not even launch. Closed by inspecting the runtime directly rather than assuming: `org.freedesktop.Platform//25.08` already carries `libepoxy.so.0` and the ffmpeg libraries (`libavcodec`/`libavformat`/`libavutil`/`libswscale`/`libswresample`) mpv links against, so neither is vendored. `libmpv` is genuinely absent, so a `libass` module and a `libplacebo`/`mpv` module pair now build it from source: `-Dcplayer=false -Dlibmpv=true` builds only the shared library mpv exposes to `media_kit_video`, not the CLI player. mpv has linked libplacebo unconditionally since 0.37, even for its plain GL output, not only its optional `vo_gpu_next` - avoiding that module by pinning mpv below 0.37 was rejected as a worse trade, since it means shipping a video-playback dependency more than two years stale for a shipping blocker fix. Both mpv and libplacebo build with Vulkan disabled (GL only), since `media_kit_video` only ever drives mpv's plain GL output and Vulkan support would add a second GPU API surface, and its own dependencies (`shaderc`, `glslang`), for no use. Built with `org.flatpak.Builder`, installed, and launched for real, twice, to isolate the fix from everything else on the build machine: the manifest without these modules reproduces the exact reported bug (`slim-m: error while loading shared libraries: libmpv.so.2: cannot open shared object file`), and the manifest with them gets straight past it, with `ldd` inside the installed sandbox confirming `libmpv.so.2`, `libepoxy.so.0`, `libass.so.9` and `libplacebo.so.360` all resolve. That run still didn't reach a window: it stopped on a separate, already-documented, unrelated defect in `packaging/flatpak/README.md` - a `GLIBC_2.43` symbol version the LiveKit Rust plugin picked up from being built on this machine's own newer glibc, not from anything media_kit touches - so a video attachment actually playing is still unconfirmed on this host. The rpm and the plain release tarball were already unaffected, since both rely on the distribution's own `mpv-libs`/`libepoxy` packages rather than the Flatpak sandbox's runtime.

The web backend is different again: `media_kit` embeds a plain HTML `<video>` element there rather than `libmpv`, and that element cannot carry the app's own bearer-token header the way a native network request can - see `attachment_video_source.dart`'s own doc comment for how each platform actually gets authenticated bytes to the player.
