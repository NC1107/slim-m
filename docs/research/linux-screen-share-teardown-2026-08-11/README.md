# Linux screen share teardown: what re-checking the research found, and a ready patch

Follow-up to PR #528 ("A screen share outliving its call") (2026-08-10).
Three things: re-verifying that entry's own claims against the real source rather than trusting them, tracing whether PR #529's client-side fix changes anything on Linux, and a prepared (not filed) upstream patch.
Read the CLAUDE.md entry first; this doc is the detail behind its correction.

## Part 1: re-verifying the prior pass's claims

Everything below was checked again directly, not carried forward.

**`libwebrtc.m144.7559.09` is confirmed**, read straight out of `third_party/libwebrtc_version.ini` inside the pinned `flutter_webrtc-1.6.0` package in the local pub cache (`~/.pub-cache/hosted/pub.dev/flutter_webrtc-1.6.0`).

**`flutter_webrtc` 1.6.0 is confirmed still the latest release**, published 2026-08-03.
`gh api repos/flutter-webrtc/flutter-webrtc/commits` shows exactly one commit past the `v1.6.0` tag on `main`: `2531fd7`, `fix(ios): restore simulator microphone capture (#2140)`, which touches only `common/darwin/Classes/FlutterWebRTCPlugin.m`.
Nothing relevant to Linux desktop capture has landed since the release this project already pins.

**`GetDisplayMedia` never registers into `video_capturers_`, confirmed by reading the current file directly.**
`common/cpp/src/flutter_screen_capture.cc`'s `GetDisplayMedia` writes the new track into `base_->local_tracks_` and the new stream into `base_->local_streams_`, and nowhere else in that function is `video_capturers_` touched.
Only the camera path (`flutter_media_stream.cc`'s `GetUserVideo`, line 433 of the fetched 1.6.0 source) writes `base_->video_capturers_[track->id()] = video_capturer;`.

**`MediaStreamTrackDispose`/`MediaStreamDispose` gate their explicit `StopCapture()` on `video_capturers_` alone, confirmed.**
`grep -rn "StopCapture(" common/cpp/ linux/ windows/ macos/` against the real 1.6.0 tree returns exactly two matches, both in `flutter_media_stream.cc`, both inside a `video_capturers_.find(...)` block.
Nothing else in the tree calls it.

**`RTCDesktopCapturer::Stop()` is confirmed already public**, read directly from the pinned SDK's own interface header (`third_party/libwebrtc/include/rtc_desktop_capturer.h`): `virtual void Stop() = 0;` on the abstract `RTCDesktopCapturer` class, callable from any code holding a `scoped_refptr<RTCDesktopCapturer>`.

**Wrong, corrected here: "this project has contributed to flutter-webrtc before" (PR #2133).**
The prior pass's claim that filing an upstream PR here would be "a precedented option, not a novel one" because of PR #2133 does not hold up.
`gh api repos/flutter-webrtc/flutter-webrtc/pulls/2133` shows it was authored by GitHub user `Quantumheart`, its own body says it was "Validated in the originating Linux desktop application (Kohera, using `livekit_client`)" - a different app, on a different account, with no reference anywhere in this repository to either name.
A direct search (`gh api search/issues -f q='repo:flutter-webrtc/flutter-webrtc author:NC1107'` and the same against `search/issues` with `creator=NC1107` on the issues list) returns zero PRs or issues from this project's own GitHub account against `flutter-webrtc/flutter-webrtc`, ever.
So PR #2133 is a genuinely similar bug in the same file, coincidentally, not a prior contribution from this project.
Filing the patch below would be a first for this account, not a repeat - a smaller thing to claim, and the accurate one.

**Nothing describing this exact symptom was found in either repo's issues or PRs, re-confirmed.**
`getDisplayMedia`/`desktop capturer`/`stop`/`leak` searches against `flutter-webrtc/flutter-webrtc` turn up #2133 itself (a different bug, same file), an unrelated Android crash report, and an unrelated Windows loopback-audio feature PR.
One real near-miss: PR #1162, "fix: Fixed the bug that the mic indicator light was still on when mic recording was stopped" (merged 2022, `common/darwin/`) - the same *shape* of bug (a still-lit OS indicator after a stop), but on iOS/macOS audio, already shipped for years, and not the desktop-capture case this patch addresses.

## Part 2: does PR #529 already close the Linux symptom?

**No - and it could not have, because the mechanism it changed has nothing to do with what tears down Linux capture.**
This is the answer that matters before the next device test.

`ScreenShareControl.stopActiveBroadcast()` (called from both `VoiceSession._teardown()` and `_onDisconnected`, per PR #529) is `BroadcastBridge.requestStop()`.
`MethodChannelBroadcastBridge.requestStop()` (`client/packages/rtc/lib/src/broadcast_bridge.dart`) opens with `if (!usesBroadcastExtension) return;`, and `usesBroadcastExtension` is `lk.lkPlatformIs(lk.PlatformType.iOS)` - false on every desktop platform.
`ScreenShareControl.dispose()` is `_cancelHandoff()` (a no-op with nothing pending) plus the same `stopActiveBroadcast()`.
So on Linux, both calls PR #529 added are pure no-ops: nothing runs, nothing is awaited that does anything.
PR #529 is real and necessary for iOS - it is the fix for the ReplayKit half of the original report - but it changes literally zero bytes of behaviour on Linux.

**What actually tears down a Linux screen-share track was already correct, and was already running on every disconnect path, before PR #529 existed.**
Traced through `livekit_client` 2.10.0 (the version this client actually locks, not the 2.8.1 named in older CLAUDE.md entries - checked in `client/pubspec.lock`):

- `Room`'s own `EngineDisconnectedEvent` listener (`lib/src/core/room.dart`, around line 596) fires on **every** engine disconnect, client-initiated or not: `await _cleanUp(disposeLocalParticipant: false)`.
- `_cleanUp` (same file, `RoomPrivateMethods` extension) calls `await localParticipant?.unpublishAllTracks();` **unconditionally**, regardless of the `disposeLocalParticipant` flag passed in.
  The flag only gates whether the `LocalParticipant` object itself is later disposed, not whether its tracks are unpublished.
- `unpublishAllTracks` calls `removePublishedTrack` for every published track, including a screen share.
  `removePublishedTrack` (`lib/src/participant/local.dart`) does two things in order: `await track.stop()` when `room.roomOptions.stopLocalTrackOnUnpublish` is true (the default, and `VoiceSession`'s own `RoomOptions` never overrides it), then `await room.engine.publisher?.pc.removeTrack(sender)`.
- `track.stop()` (`LocalTrack.stop()` in `lib/src/track/local/local.dart`, overriding `Track.stop()`) calls `mediaStreamTrack.stop()` (native `trackDispose` → `MediaStreamTrackDispose`, dropping the plugin's own `local_tracks_` map entry and the stream's own `RemoveTrack`) and separately `mediaStream.dispose()` (native `streamDispose` → `MediaStreamDispose`, dropping `local_streams_`).
- `pc.removeTrack(sender)` drops the RTP sender's own hold on the track.

That is all three references this project's own research already named (the stream, the plugin's `local_tracks_`/`local_streams_` maps, the peer connection's sender), all dropped, in order, awaited, on **every** disconnect - because `Room`'s internal listener runs this before it ever emits the `RoomDisconnectedEvent` that `VoiceSession._onDisconnected` listens for.
`_onDisconnected`'s own doc comment already said "LiveKit's own engine already unpublishes and stops every local track for this case" - traced now rather than taken on faith, and it holds exactly as stated, for the reason given above (the unconditional `unpublishAllTracks()` inside `_cleanUp`, not merely "an engine disconnect runs some cleanup").

Once all three references drop, C++ refcounting is synchronous, not deferred: `ScreenCapturerTrackSource`'s destructor (`~ScreenCapturerTrackSource() { capturer_->Stop(); }`) runs the instant its own last reference goes, and the member `capturer_`'s own destructor runs immediately after, in the same call, dropping the last reference to `RTCDesktopCapturerImpl` and running *its* destructor (`thread_->Stop(); capturer_.reset();`) - the line that actually destroys the real `webrtc::DesktopCapturer`, the object presumably backing whatever OS-level session (PipeWire portal, X11 grab) drives the recording indicator.
Confirmed the ownership chain has no other retaining reference: `CreateDesktopSource_d` in `webrtc-sdk/libwebrtc`'s `rtc_peerconnection_factory_impl.cc` constructs exactly one `ScreenCapturerTrackSource(capturer)`, and the `desktop_capturer` local variable in `GetDisplayMedia` goes out of scope once that function returns.

**So: nothing in this client's Dart teardown ordering, before or after PR #529, was ever the reason a Linux recording indicator would stay lit.**
The reference-dropping chain was already complete and already synchronous on both the clean-leave path and the forced-disconnect path.
If the owner's next test on Linux still shows the indicator staying lit, PR #529 is not what would have fixed it, and the cause is one of:

1. The asymmetry this whole investigation already named: the *implicit* stop above is real and does run, but it depends on every reference actually dropping, which is a chain of several `await`s across two packages - fragile in the sense that a future code path (a different unpublish sequence, a renderer/texture holding its own reference for a self-preview, a bug in some future LiveKit version that skips `unpublishAllTracks` on one path) could silently break it with no explicit signal that it did.
   The patch below closes that fragility without depending on it being the current cause.
2. A platform/portal-level issue this source tree cannot see at all - some `xdg-desktop-portal` implementations are known to lag or fail to clear their own indicator promptly even once the client-side `ScreenCastSession` is properly torn down, which is a desktop-environment bug not addressable from this codebase.
3. Something in the client's own UI layer (a self-preview widget rendering the local share back to the sharer, if one exists and is not unmounted promptly on hangup) retaining an extra renderer/texture reference past what `VoiceSession` itself controls - out of this investigation's scope (client app UI is owned by other in-flight work) and not checked here.

None of the three can be told apart without a real Linux desktop and someone watching the system's own recording indicator after a hangup - the same evidentiary gap the original CLAUDE.md entry already named, and the same reason this box must not be used to test it.

## Part 3: the patch, prepared and not filed

Same shape the prior pass recommended, written and checked against the real pinned headers rather than only reasoned about.

**What it does.** Adds a second map, `desktop_capturers_`, alongside the existing `video_capturers_` in `FlutterWebRTCBase` (`common/cpp/include/flutter_webrtc_base.h`).
`GetDisplayMedia` (`common/cpp/src/flutter_screen_capture.cc`) populates it with the same `scoped_refptr<RTCDesktopCapturer>` it already holds locally, keyed by the track id - the same key `local_tracks_`/`video_capturers_` already use.
`MediaStreamTrackDispose` and `MediaStreamDispose` (`common/cpp/src/flutter_media_stream.cc`) each gain a block that mirrors the existing `video_capturers_` block exactly: look up the track id, call `IsRunning()`/`Stop()` explicitly if found, erase the entry.
`rtc_desktop_capturer.h` needed adding to `flutter_media_stream.cc`'s own includes - `RTCDesktopCapturer` is only forward-declared through the headers that file already pulls in, and the full type is needed to call `IsRunning()`/`Stop()` on it or to copy/destroy the `scoped_refptr`.

**Why it is still worth proposing, independent of Part 2's finding that the implicit path already works today.**
It is the same asymmetry-closing shape the camera path already has, makes the stop explicit and immediate rather than dependent on a chain of `await`s and refcounting all landing correctly, and costs nothing on any platform: a second small map keyed identically to the one beside it.
If Part 2's reasoning about the implicit path is wrong in some way this trace missed, or breaks in a future LiveKit or app version, this patch is what would have caught it anyway.

**Compiles.** Confirmed with `g++ -std=c++17 -fsyntax-only`, `-DRTC_DESKTOP_DEVICE -DWEBRTC_LINUX`, against the real headers: this repo's own `common/cpp/include`, the pinned `flutter_webrtc-1.6.0`'s fetched `third_party/libwebrtc/include` and `linux/flutter/include` (pub.dev ships these pre-fetched; a fresh git clone does not, since `third_party/libwebrtc/` is gitignored and fetched by CMake at configure time), and the local Flutter SDK's own vendored `flutter_linux` embedder headers (`~/development/flutter/bin/cache/artifacts/engine/linux-x64/flutter_linux`).
Both edited translation units (`flutter_screen_capture.cc`, `flutter_media_stream.cc`) compile clean under that flag - not a full CMake/ninja build or link against the real prebuilt `libwebrtc` binary, which would need downloading and linking a large closed-source release archive; that step was judged an unreasonable build for this pass and was not attempted.
This is real evidence the patch is type-correct against the actual pinned SDK, short of a full link.

**How to file it, if the owner wants to.** `desktop-capturer-explicit-stop.patch` in this directory applies cleanly against a clone of `flutter-webrtc/flutter-webrtc` at the `v1.6.0` tag (`git apply docs/research/linux-screen-share-teardown-2026-08-11/desktop-capturer-explicit-stop.patch`, run from the clone's root).
Match PR #2133's shape and tone for the PR body: a short **Problem** section (the asymmetry between camera and desktop-capture dispose paths, cited to the exact lines), a **Fix** section (the three edits above), and a **Testing** section stating plainly what was and was not verified - syntax-checked against the pinned headers, not built, not run against a real desktop.
Not filed in this pass, per the owner's own standing instruction that this kind of external contribution should go out under his own account if he wants it to, not an agent's.

**Deliberately not done: a `dependency_overrides` fork pin.**
Considered again here and rejected for the same reason PR #528 already gives: Part 2's trace found the implicit path already correct and already running on every disconnect, so a forked pin would carry the ongoing cost this project has a recorded scar about, for a fix whose payoff (over the already-working implicit path) is unverified without a device.
