<!-- SPDX-License-Identifier: Apache-2.0 -->
# Android backlog

See [README.md](README.md) for what "confirmed" and "suspected" mean here and how this differs from `docs/BACKLOG.md` and `docs/OPEN-QUESTIONS.md`.

Android has a real, scaffolded, signed CI pipeline (`main-builds.yml`'s `android-client` job builds and verifies a signed apk and appbundle on every merge; `release.yml` ships them on tagged releases) and real production credentials (a Play Console app, an upload keystore, Firebase/FCM).
What it has never had is a real device.
`docs/OPEN-QUESTIONS.md` section 2 states this as plainly as it can be stated: "no Android device has ever been available, and no CI check can see a missing runtime permission."
Read every "confirmed" entry below with that in mind: "confirmed" here generally means confirmed in source, in the manifest, or by CI signing verification, not confirmed on hardware, and each entry says which.

## Confirmed

**`RECORD_AUDIO` was missing from the Android manifest from the day voice shipped until PR #231, so a call on Android could never have captured audio, and nothing caught it for the whole period it was missing.**
`docs/OPEN-QUESTIONS.md` section 2, and confirmed present now by reading `client/packages/app/android/app/src/main/AndroidManifest.xml` directly (`android.permission.RECORD_AUDIO` is declared).
The permission is fixed; **the fix itself is unverified on real hardware**, because, per the same section, "no Android device has ever been available."
This is one of the clearest examples in this project of a category of bug no automated check can see: a missing runtime permission has no compile-time or unit-test signal at all.

**There is no `android.telecom.ConnectionService` integration; incoming calls surface as a `NotificationCompat.CallStyle` notification instead, and this is a deliberate, documented, and only half-complete answer to the roadmap's own stated deliverable.**
Confirmed by reading `client/packages/platform/android/src/main/kotlin/top/npcserver/slimm/platform/IncomingCallNotifier.kt`'s own doc comment: "One `NotificationCompat.CallStyle` code path covers every API level this app ships (minSdk 24): androidx renders the real `Notification.CallStyle` chrome on API 31+, and an equivalent plain notification with the same answer and decline actions on everything older... There is no ConnectionService/`android.telecom` registration here."
`docs/ROADMAP.md`'s Phase 4 status makes the gap against the original deliverable explicit: "An Android incoming-call notification ships `NotificationCompat.CallStyle` with an optional full-screen intent, by its own commit message explicitly *not* `android.telecom.ConnectionService` integration, so this phase's 'Android ConnectionService with a CallStyle notification' deliverable is still only half built."
Practical consequence, inferred from how `ConnectionService` differs from a plain notification: without it, Android does not treat this app's calls as first-class system calls (no native in-call UI integration, no automatic Bluetooth/car-mode routing, no appearance in the system's own recent-calls list), even though the notification itself renders correctly.

**`NotificationManagerCompat.canUseFullScreenIntent` is checked per call rather than once, because Android 14 lets the user revoke full-screen-notification permission live while the app is running.**
Confirmed by reading `IncomingCallNotifier.kt`'s doc comment directly. Recorded as a rule worth keeping: any future touch of this notifier should not "optimize" that into a cached, checked-once value.

**Per-participant call volume (`Helper.setVolume`) is one of the three platforms confirmed to actually work.**
Confirmed from `CLAUDE.md`'s "Moderating a member" section: "Android, iOS, macOS work. Their native track lookups fall back to scanning the peer connection's transceivers, so a remote track is found." `client/packages/rtc/lib/src/audio_gain.dart`'s `supportsParticipantVolume` includes Android in its allow-list (confirmed by reading the file). This specific behaviour is read from source and matches the documented platform split, but - consistent with the rest of this file - has not itself been confirmed with a live multi-participant call on a real Android device.

**Camera background blur on Android has a real native per-frame hook, unlike Linux and Windows, but the model that would run behind it does not fit the frame budget on a real, current-generation phone, per a primary-sourced measurement.**
`docs/research/background-blur-spike.md`: Android's WebRTC plugin layer (`com.cloudwebrtc.webrtc.video.LocalVideoTrack`) implements `org.webrtc.VideoProcessor` directly and exposes `addProcessor(ExternalVideoFrameProcessing)`, handed a real `org.webrtc.VideoFrame` per call - genuine native access, though "nothing in the Dart layer calls it" today.
The blocking finding is the model, not the hook: [google-ai-edge/mediapipe issue #5954](https://github.com/google-ai-edge/mediapipe/issues/5954), a primary-sourced report against a **Google Pixel 9** (a current flagship, not budget hardware) running the standard `selfie_segmenter.tflite` model, measured "90+ ms on average" on the CPU delegate against a 33.3ms frame budget at 720p30, with the GPU delegate - the one path that would fit the budget - reported to "completely fail or become extremely slow, or on certain devices, appears to crash" for this exact task.
Downsizing the input to save time was also tried in that same report and got to roughly 60ms, still nowhere near budget, with "unacceptably poor segmentation" in the reporter's own words.
The spike's own conclusion, worth stating directly: "If Android is pursued, it needs its own measurement on real target hardware before any budget claim is made, not an assumption carried over from this spike." See [ios_backlog.md](ios_backlog.md) and [macos_backlog.md](macos_backlog.md) for the platforms where the same feature has a more promising path (Apple's Vision framework), and [linux_backlog.md](linux_backlog.md) and [windows_backlog.md](windows_backlog.md) for the two platforms with no native hook at all.

**Android's clipboard image paste path (the composer's "+" sheet "Paste image" row) is Android's *only* route to a pasted image, and it is entirely unverified on a real device.**
`CLAUDE.md`, "Image paste on iPhone, confirmed working": "The '+' sheet row is Android's **only** route to a pasted image - there is no edit-menu swizzle there at all." The same entry closes with: "Android's clipboard path is still unverified on a device; `ClipboardImageChannel.kt` and the '+' sheet row on Android are reasoned from source and covered by unit tests only, the same unverified state every mobile surface here was in before this pass. Do not read this entry as proving the whole feature works on both platforms - iOS is closed, Android is not." Confirmed by reading `client/packages/app/android/app/src/main/kotlin/top/npcserver/slimm/ClipboardImageChannel.kt`, which exists and implements the platform-channel read, but has never been exercised end to end on hardware.

**Building the Android target locally on this project's own Linux development machine needs a JDK the OS does not ship, and the fix is a documented, user-local workaround rather than a system package.**
`CLAUDE.md`, "Local development": Fedora 44 ships only a JRE with no `javac`, so the first Android build fails with "does not provide the required capabilities: [JAVA_COMPILER]"; the fix is a user-local Temurin 21 wired in via `flutter config --jdk-dir=...`, specifically JDK 21 (not the packaged 25) because that is the LTS the Android Gradle Plugin actually supports. This is a build-environment fact rather than an app bug, and is recorded here because it affects anyone reproducing an Android build issue on a similar Linux dev setup, not just this project's own machine.

**CI verifies the release apk is signed with the real, Play-registered upload key rather than a debug key, and this check has a specific, quotable failure mode worth knowing.**
Confirmed by reading `main-builds.yml`'s `android-client` job: it runs `apksigner verify --print-certs` on the built release apk and hard-fails if the debug keystore's own name (`Android Debug`) is found in the output, or if the signer's sha256 fingerprint does not match a hardcoded expected value (`9dc12a6a03bd6125065fb5f6eca2d8d8477f74009e0f6624efee2d2b98ec033b`, documented in the workflow as "Play's registered upload certificate fingerprint; public, not a secret"). This is a real, load-bearing CI gate, not a lint - it is what stops a misconfigured `key.properties` from shipping a debug-signed release apk without anyone noticing.

**Android push wake (a backgrounded device receiving a content-free push and fetching the message) is the last unclosed Phase 3 exit criterion, and it is explicitly a hardware gap, not a code gap.**
`docs/ROADMAP.md`'s Phase 3 status: "Android device wake is not met, and is explicitly a hardware gap: no Android device test exists anywhere, and no Android hardware has been available to run one." The registration path, the pipeline, and the cross-repo envelope contract test (`push-relay-contract.yml`) are all built and green; only the real-device leg is missing.

## Suspected

**Whether the fixed `RECORD_AUDIO` permission actually results in a working call on Android is unverified**, since the permission being declared and a call actually capturing audio through it on real hardware are two different claims, and only the first has any evidence. `docs/OPEN-QUESTIONS.md` section 2 poses this directly as an open question for the owner: "is an Android device likely to be available at some point, or should the Android call path be treated as unsupported and said so in the docs rather than shipped untested?"

**The Android incoming-call notification's full-screen intent, answer/decline actions, and interaction with a locked or backgrounded device have never been observed on real hardware.** This follows from the same absence of Android hardware noted throughout this file; the code is read directly from source (see the confirmed entry above) but has no device-observed behaviour to cite.

**Whether Android's GPU-delegate failure for MediaPipe segmentation (cited in the confirmed camera-blur entry) is specific to the exact API surface used in the primary-sourced report, or would also affect a different integration path, is explicitly unresolved by the spike itself.**
`docs/research/background-blur-spike.md`'s own "what this spike did not settle" section: "Whether Android's GPU delegate failure in the cited issue is specific to MediaPipe Tasks 0.10.14 or also affects a raw `tflite_flutter` integration bypassing MediaPipe Tasks entirely; the underlying TFLite GPU delegate is shared, but this was not independently confirmed."

**Play internal testers have never received a build, so nothing about the real end-user install-and-open experience on Android has ever been observed, even setting aside voice.**
`CLAUDE.md`, "Push credentials and identifiers": "First AAB 0.1.0 (4) is on the internal testing track; no testers added yet by owner choice." `docs/OPEN-QUESTIONS.md` section 4 confirms this remains an owner-only action, since no Play Developer API credential exists in this environment to automate it.
