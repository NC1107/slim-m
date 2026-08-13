<!-- SPDX-License-Identifier: Apache-2.0 -->
# Windows backlog

See [README.md](README.md) for what "confirmed" and "suspected" mean here and how this differs from `docs/BACKLOG.md` and `docs/OPEN-QUESTIONS.md`.

The single fact that reframes every entry below: **there is no Windows client target in this repository.**
Everything downstream of that is unverifiable rather than broken, and should be read that way.

## Confirmed

**No `windows/` platform directory exists under `client/packages/app`.**
Confirmed by listing the directory: it holds `android`, `ios`, `linux` and `web` only.
There is nothing to `flutter build windows` yet.
*Action, and it comes before anything else in this file*: scaffold the platform (`flutter create --platforms=windows .` from `client/packages/app`, following the same shape the `linux/` directory already has) and add a compile-only CI job before any other Windows item in this file is treated as more than a prediction.

**No CI workflow builds, tests, or even type-checks a Windows target.**
Confirmed by reading every file in `.github/workflows/`: `client-ci.yml` runs `dart analyze`, `flutter test` and `flutter build web` on `ubuntu-latest`; `main-builds.yml` and `release.yml` build Linux (`ubuntu-latest`), Android (`ubuntu-latest`) and iOS (`macos-latest`), and neither file has a `windows-latest` runner or a `flutter build windows` step anywhere.
`e2e.yml` drives the **web** build in headless Chrome on `ubuntu-latest`, which exercises no desktop-native code path on any OS.
There is consequently no automated signal, of any kind, for a Windows regression today, because there is no Windows build for one to regress.

**No Windows packaging exists, and none is documented as planned.**
Confirmed: `packaging/` holds `fedora/`, `linux/` and `rpm/` only.
`docs/ROADMAP.md`'s Phase 9 (release readiness) names "Linux artifacts (Flatpak primary, rpm alongside) and the iOS TestFlight-to-production path" as its packaging deliverable and does not name an MSI, an installer, a winget manifest, or any other Windows artifact anywhere in the document.
This is worth stating plainly rather than assuming it is simply unwritten yet: no phase in the roadmap currently has a Windows packaging deliverable at all.

**The `win32` package family's version is already load-bearing on every platform, including this one, before Windows is even scaffolded.**
`docs/dependencies.md` ("Client holds"): `livekit_client` 2.8.1 pins `device_info_plus` to a version capping the transitive `win32` package at major version 5, while `file_picker` 12 needs `win32` 6, so the whole dependency tree had to move together rather than holding one package back.
Its own text: "this was never a Windows-only concern: those libraries type-check on a Linux build even though none of their code ever runs there, so a `win32` major mismatch is a hard build failure on every platform."
*The rule that follows, stated in the same file and worth repeating here*: if a future `win32`-dependent package conflict recurs, the fix is to follow whatever `livekit_client` pins, not to bump the other `win32` packages on their own merits.
Check `docs/dependencies.md` before touching `file_picker`, `device_info_plus`, `package_info_plus`, or `flutter_secure_storage`.

**`audioplayers_windows` is already resolved in the committed lockfile.**
Confirmed by grepping `client/pubspec.lock`: `audioplayers_windows` is a resolved transitive dependency of `audioplayers`, the package `docs/dependencies.md` documents choosing for the notification-sound slice (`CLAUDE.md`, "The seven sounds finally play: the in-app slice").
This means the dependency graph is already Windows-capable for audio playback in principle; it does not mean playback has ever been exercised on Windows, since nothing builds for it yet.

**The bundled notification-sound assets are a git symlink, and CLAUDE.md's own reasoning for why that is safe explicitly excludes Windows.**
Confirmed: `git ls-files -s client/packages/app/assets/audio/notifications` reports mode `120000` (a symlink), pointing at `../../../../../assets/audio/notifications`.
`CLAUDE.md` ("The seven sounds finally play: the in-app slice") states this directly: "Windows is not a real cost here: no workflow in this repo builds a Windows client, so `core.symlinks` never needs to be true anywhere CI runs."
That sentence is a statement that the problem was deliberately not solved, not that it does not exist - see the suspected entry below for what it implies once a Windows target exists.

**`Helper.setVolume` (per-participant call volume) is documented as throwing on Windows, and the client already guards against calling it there.**
Confirmed from `CLAUDE.md`'s "Moderating a member" section: Windows and Linux share flutter_webrtc's `common/cpp` native layer, whose track lookup only scans a `remote_streams_` map filled by the Plan B `OnAddStream` callback; LiveKit uses Unified Plan, so that map is always empty and the call throws "Unable to find provided track".
`client/packages/rtc/lib/src/audio_gain.dart`'s `supportsParticipantVolume` is already gated to Android, iOS and macOS only (`lk.lkPlatformIs` checks for those three, confirmed by reading the file), so Windows is already correctly excluded and the slider will not render there once the platform exists.
*The rule to keep*: never add a call path that reaches `Helper.setVolume` without going through this same platform gate.

**Camera background blur has no native per-frame hook on Windows at all, and this is explicitly "absent," not "unwired."**
Confirmed from `docs/research/background-blur-spike.md` (2026-08-01), which grepped the pinned ~~`flutter_webrtc` 1.4.0~~ source tree directly: "Linux and Windows have no native per-frame hook at all in the WebRTC plugin this project depends on: not missing wiring, missing entirely."
Version correction 2026-08-11: `client/pubspec.lock` resolves that package at **1.6.0** now; the finding was re-checked against the newer tree on 2026-08-10 and the native surface had not changed, so only the version number was stale.
The only path that document identifies for Windows is a genuine upstream contribution to `flutter_webrtc`'s shared `common/cpp` layer, or a from-scratch capturer - both well outside this project's own timeline.
The spike's own recommendation, worth carrying forward verbatim: ship blur where a real seam exists (iOS/macOS) and gate the camera toggle off, or clearly label it as unblurred, on platforms without one, rather than silently shipping raw camera everywhere or blocking camera indefinitely on a seam that will not exist uniformly for a long time. See [macos_backlog.md](macos_backlog.md) and [linux_backlog.md](linux_backlog.md) for the same finding on those platforms.

## Suspected

**The notification-sound symlink will very likely check out as a broken plain-text file on a native Windows clone, once a Windows target exists.**
Inferred from the confirmed symlink above and standard git behaviour: without `core.symlinks=true` set (which git on Windows does not default to, and which requires either Developer Mode or an elevated `git clone`), a symlinked file materialises on checkout as an ordinary text file containing the literal target path string, not the directory it points at.
`notification_sound_bundle_test.dart` (cited in `CLAUDE.md`) checks that all seven `rootBundle` keys load and are non-empty, but that test runs under `client-ci`'s `flutter test` on `ubuntu-latest`, so it would not catch this on a genuine Windows build even once one exists.
*What would confirm or refute this*: once the platform is scaffolded, do a real `git clone` on a Windows machine without `core.symlinks` set and check what `assets/audio/notifications` actually contains; if this is confirmed, the fix is either a real (non-symlinked) copy of the asset directory for the Windows target, or setting `core.symlinks=true` in whatever CI checkout step builds Windows plus a documented contributor requirement (Developer Mode or an elevated clone) for anyone building it locally.

**Screen-share audio (2026-08-13) has a real native implementation waiting for Windows, unlike the camera-blur hook a few entries up, which genuinely has none.**
`flutter_webrtc`'s `windows/application_loopback_capturer.cc` implements the same `LoopbackCapturer` interface (`common/cpp/include/loopback_capturer.h`) Linux's PulseAudio path does, over WASAPI's application-loopback API, and would be reached through the identical `GetDisplayMedia`/`captureScreenAudio` seam this project's `client/packages/rtc/lib/src/screen_share_audio.dart` now uses for Linux.
`supportsScreenShareAudio` correctly excludes Windows today, for the same reason every capability in this file is excluded: there is no Windows target to enable it for, not because the underlying capture is missing the way it is on macOS, iOS and Android.
*What would confirm or refute this*: once Windows is scaffolded, the same enumerate-then-capture-then-check-for-an-audio-track probe this file's other screen-share entry already asks for, extended to request `includeAudio: true` and check whether a real audio track is published.

**Screen share is entirely unverified on Windows, in either direction.**
`docs/research/reference-echo-messenger.md` and CLAUDE.md's Linux findings establish real, tested behaviour for Fedora Wayland (a segfault on window enumeration, fixed by never requesting `SourceType.Window`) and a working owner-confirmed screen share on Linux in general.
Nothing in this repository, any CI workflow, or any research document exercises `getDisplayMedia`/`desktopCapturer.getSources` on Windows.
`client/packages/rtc/lib/src/desktop_sources.dart`'s own doc comment notes, in passing, that "macOS and Windows have no such native picker of their own, so this app's sheet stays their only one" - meaning the app's own source-selection sheet (not an OS compositor picker) is expected to be the only chooser on Windows, unlike the Wayland case where the portal supplies one.
That is read from source, not observed running, so it is suspected rather than confirmed: whether `flutter_webrtc`'s Windows desktop capturer enumerates and captures correctly at all has never been checked in this project.
*What would confirm or refute this*: once Windows is scaffolded, run the same enumerate-then-capture probe CLAUDE.md describes doing for Fedora ("enumerating screens returns one source... capture with that id publishes a track").

**`tflite_flutter`'s Windows native build path is unverified, and the package's own README frames desktop support as meaningfully different from mobile support.**
`docs/research/background-blur-spike.md`'s survey table lists `tflite_flutter` as covering Windows "with manual native build" versus "automatic" on Android/iOS, and the document states directly: "I did not attempt to build `tflite_flutter`'s desktop path in this environment... Whether it actually links on this project's own Fedora KDE Wayland target is unverified," with the same uncertainty extended explicitly to "Windows/macOS CI runners" in the spike's own "what this spike did not settle" section.
This only matters if camera blur is ever attempted on Windows via that specific library; the spike's own recommendation is not to build it there at all given the missing native hook (see the confirmed entry above), so this is recorded for completeness rather than as a near-term blocker.

**A frameless, custom title bar would need Windows-specific chrome, and nothing has been built ~~or spiked~~ for it.**
Half corrected 2026-08-11: it has now been spiked, in [decision 0012](../decisions/0012-desktop-window-shell.md), which designs the whole desktop window shell and was built for Linux in PR #533.
Nothing Windows-specific was built, and that record says so about itself in its own words - every Windows statement in it "is a design intent to build against once a platform exists, not a tested fact," since this client still has no `windows/` directory.
So the shape is decided and waiting rather than unconsidered.
`docs/BACKLOG.md`'s "A frameless window with our own title bar" entry (deferred, not declined) names the shape directly: "Three platforms want three different things: macOS traffic lights top-left with specific insets, Windows controls top-right, Linux depending on the desktop environment.
A single custom bar that ignores that feels foreign on at least two of them."
Window dragging, double-click-to-maximise, edge snapping, the system menu, and keyboard/screen-reader reachability for window controls would all need reimplementing for Windows specifically if this is ever picked up; none of it exists today, and it is deferred rather than scheduled. See the same entry noted in [macos_backlog.md](macos_backlog.md) and [linux_backlog.md](linux_backlog.md).

**`flutter_secure_storage`'s Windows backend (Credential Locker, via the `win32` package) has never been exercised.**
`client/packages/platform/pubspec.yaml` depends on `flutter_secure_storage: ^10.3.1`, which is the seam `persistent_key_store.dart` uses for the E2EE key-storage groundwork (`CLAUDE.md`'s design-alignment section: "a key-storage interface shaped so a future move to hardware-backed non-extractable keys needs no interface change").
The package's own Windows plugin resolves in the dependency tree (as part of the `win32`-coupled family discussed above), but no test or build in this repository has ever run its Windows storage backend, so whether it round-trips a stored secret correctly on that platform is unknown rather than assumed working.
