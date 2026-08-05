<!-- SPDX-License-Identifier: Apache-2.0 -->
# macOS backlog

See [README.md](README.md) for what "confirmed" and "suspected" mean here and how this differs from `docs/BACKLOG.md` and `docs/OPEN-QUESTIONS.md`.

The same reframing as Windows applies here: **there is no macOS client target in this repository.**
`macos-latest` GitHub runners are already used in this project, but only to build and test the **iOS** app; nothing on them builds a native macOS desktop client.
Everything below is unverifiable rather than broken, and should be read that way.

## Confirmed

**No `macos/` platform directory exists under `client/packages/app`.**
Confirmed by listing the directory: it holds `android`, `ios`, `linux` and `web` only.
`flutter create --platforms=macos .` (or equivalent, mirroring the existing `linux/` and `ios/` directories) has never been run.
*Action, and it comes before anything else in this file*: scaffold the platform and add a compile-only CI job on `macos-latest` before any other item in this file is treated as more than a prediction.
This project already pays for `macos-latest` minutes (`client-ios-ci.yml`, `main-builds.yml`'s `ios-testflight`, `release.yml`'s `ios-testflight`), so a macOS desktop compile job is a marginal addition to an existing runner class rather than a new cost category.

**No CI workflow builds, tests, or type-checks a macOS desktop target.**
Confirmed by reading every file in `.github/workflows/`: the only `macos-latest` jobs anywhere (`client-ios-ci.yml`'s XCTest job, and the `ios-testflight` jobs in `main-builds.yml` and `release.yml`) build and sign the **iOS** app (`flutter build ipa`), never `flutter build macos`.
There is consequently no automated signal, of any kind, for a macOS desktop regression today.

**No macOS packaging exists, and none is documented as planned.**
Confirmed: `packaging/` holds `fedora/`, `linux/` and `rpm/` only.
`docs/ROADMAP.md`'s Phase 9 packaging deliverable names Linux (Flatpak, rpm) and the iOS TestFlight path; it does not name a `.dmg`, a notarization step, a Homebrew cask, or the Mac App Store anywhere.

**Per-participant call volume (`Helper.setVolume`) is one of the three platforms confirmed to actually work, unlike its Linux and Windows siblings.**
Confirmed from `CLAUDE.md`'s "Moderating a member" section: "Android, iOS, macOS work. Their native track lookups fall back to scanning the peer connection's transceivers, so a remote track is found."
`client/packages/rtc/lib/src/audio_gain.dart`'s `supportsParticipantVolume` already includes `lk.PlatformType.macOS` in its allow-list (confirmed by reading the file), so once a macOS target exists this control should already be correctly enabled by the platform gate with no further client-side change needed.
This is the strongest positive signal anywhere in this file: it is read from source and matches the code that already ships and is tested on the two platforms (iOS, Android) that do have a real target.

**macOS has the most promising path to camera background blur of any desktop platform, and it still needs new native code that does not exist yet.**
Confirmed from `docs/research/background-blur-spike.md`: macOS shares the same `VideoProcessingAdapter`/`ExternalVideoProcessingDelegate` native hook as iOS (`common/darwin/Classes/`, mirrored into `macos/Classes/` inside `flutter_webrtc`), and Apple's Vision framework (`VNGeneratePersonSegmentationRequest`, iOS 15+/macOS 12+) is a first-party, no-dependency, Neural-Engine-accelerated segmentation model available on macOS with no bundled model or extra licence.
The spike is explicit that this hook has **no Dart binding today**: "grepping every native `.m` file for callers of `addProcessing:` finds only the plugin's own internal use... never a `MethodChannel` handler that would let Dart register one."
Building it would be "genuinely buildable today with no new third-party dependency," in the spike's own words, and is described as the same shape of work as the existing `BroadcastBridge` Swift bridge already shipped for iOS screen share (`CLAUDE.md`, "The one-flag iOS screen share fix").
*Action, if camera blur is ever prioritized*: macOS (bundled with the iOS-first work, since both use the same darwin native hook and the same Vision-framework model) is the platform most likely to be worth doing first, per the spike's own recommendation, once camera publishing itself ships.

## Suspected

**No measured performance number exists anywhere for the Vision-framework segmentation path, on macOS or iOS.**
`docs/research/background-blur-spike.md` is explicit about this gap in its own "what this spike did not settle" section: "A measured inference number for Apple's Vision framework on a real iPhone. Only a vendor 'milliseconds' claim and one anecdotal report of lag in an unrelated integration" (a developer forum thread describing a lagging feed from `VNGeneratePersonSegmentationRequest` "in a macOS camera-extension integration," found by search and explicitly not independently verified by the spike itself).
The frame-budget analysis in that document is measured only for Android (a Pixel 9, via a primary-sourced GitHub issue), not for any Apple platform.
This does not contradict the confirmed entry above that macOS/iOS have the best available *seam*; it means "the seam exists and is fast per Apple's own claim" is one step short of "measured fast enough on this project's own target hardware."

**Screen share is entirely unverified on macOS, in either direction.**
The confirmed, tested screen-share findings in this project (the Fedora Wayland segfault-on-window-enumeration bug and its fix, the iOS `BroadcastManager` double-capture collision and its fix) are both platform-specific and neither transfers to macOS by inference.
`client/packages/rtc/lib/src/desktop_sources.dart`'s doc comment notes, read from source rather than observed running, that "macOS and Windows have no such native picker of their own, so this app's sheet stays their only one" - the same point made in the Windows file, meaning the app's own source-picker sheet is expected to be macOS's only chooser, unlike Linux's Wayland portal.
Whether `flutter_webrtc`'s macOS desktop capturer actually enumerates and captures screens correctly has never been checked here.
*What would confirm or refute this*: once macOS is scaffolded, run the same enumerate-then-capture probe CLAUDE.md describes for Fedora.

**Notarization, code signing, and Gatekeeper are entirely unaddressed.**
This project already has real, working Apple code-signing infrastructure for iOS (an Apple Developer team, a distribution certificate, App Store Connect API credentials, provisioning-profile handling documented in `CLAUDE.md`'s "Driving the Apple Developer portal" and "Push credentials and identifiers" sections), which is the closest existing precedent for what a signed, notarized macOS build would need.
No macOS-specific certificate, notarization credential, or `codesign`/`notarytool` step exists anywhere in this repository or its workflows.
This is inferred from the total absence of macOS build infrastructure rather than confirmed as a specific blocker, since nobody has attempted it; it is recorded because an unsigned or unnotarized macOS build is effectively unusable for most users (Gatekeeper blocks it by default), so this is not optional polish once a macOS target ships.

**A frameless, custom title bar would need macOS-specific chrome (traffic-light window controls, top-left, with specific insets), and nothing has been built or spiked for it.**
`docs/BACKLOG.md`'s "A frameless window with our own title bar" entry names this directly, deferred rather than declined: "macOS traffic lights top-left with specific insets, Windows controls top-right, Linux depending on the desktop environment. A single custom bar that ignores that feels foreign on at least two of them."
See the same entry noted in [windows_backlog.md](windows_backlog.md) and [linux_backlog.md](linux_backlog.md).

**`flutter_secure_storage`'s macOS backend (Keychain) has never been exercised, though it is the most standard of the desktop backends.**
`client/packages/platform/pubspec.yaml` depends on `flutter_secure_storage: ^10.3.1` (the same key-storage seam noted in the Windows file), and its `flutter_secure_storage_darwin` plugin (confirmed present in `client/pubspec.lock`, shared between iOS and macOS) backs both platforms' Keychain access with the same code.
Because this plugin already ships and is presumably exercised indirectly via the iOS build, it is the single lowest-risk unverified item in this file; it is listed as suspected only because no macOS-specific test or build has ever actually run it.
