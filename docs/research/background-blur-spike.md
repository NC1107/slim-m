# Camera background blur/replacement spike

Status: research spike, no production code.
Date: 2026-08-01.
Scope: whether background blur or replacement on the camera track is achievable on this stack, and at what cost, ahead of the camera-publish work itself.
Not a design for the camera feature. Not an implementation.

Why this exists: `docs/BACKLOG.md` records the owner calling background blur "kindve a required feature" and a camera-launch blocker, not polish.
The camera publish path is not built yet (`docs/ROADMAP.md` still lists camera pre-toggle as the one missing piece of Phase 4 voice UX), so this spike runs before that work picks an architecture, not after.

## Verdict up front

**Build a reduced version, scoped by platform, not a uniform day-one feature.**
There is no seam anywhere in this stack, on any platform, that hands a Flutter app a decoded video frame it can run a model over and hand back.
The one platform with a real, fast, first-party answer (Apple's Vision framework, on iOS and macOS) still needs new native Swift/ObjC glue of about the size this project's existing `BroadcastBridge` work already is.
Android has a native per-frame hook too, but the model that would run behind it measures too slow to hit a video frame budget on a real, current-generation Android phone, per a primary-sourced GitHub issue below, and its GPU delegate path is reported broken for this exact task.
Linux and Windows have no native per-frame hook at all in the WebRTC plugin this project depends on: not missing wiring, missing entirely.
Web has the best underlying platform primitive of the six but needs hand-written JavaScript interop to reach it, since neither `flutter_webrtc` nor `livekit_client` wire it up.
Shipping camera with blur only where blur can actually be built, and gating the camera toggle off (or clearly labelled) elsewhere, is the honest middle path between shipping raw camera everywhere and blocking camera indefinitely on a universal seam that does not exist today and cannot be assembled uniformly given the Linux/Windows gap.

## What was checked, and how

Every claim about `livekit_client` and `flutter_webrtc` below is read from the exact versions this repo depends on, not from memory of the API shape.
`client/packages/rtc/pubspec.yaml:12-13` pins `livekit_client: ^2.8.1` and `flutter_webrtc: ^1.4.0`; `client/pubspec.lock` resolves those to `livekit_client-2.8.1` (`sha256:bd68a1e2...`) and `flutter_webrtc-1.4.0` (`sha256:8b220dc0...`), with `webrtc_interface-1.5.1` underneath.
All three are present under `~/.pub-cache/hosted/pub.dev/`, so the sources quoted here are the real, installed package code, not a newer or older release.
Where the answer needed public repository history (issues, changelogs, PRs), those are cited by URL and were read directly via `gh api` or fetched, not paraphrased from a search summary; two places below where a search-engine synthesis produced a number I could not corroborate from a primary source are called out and set aside rather than used.

## 1. Does livekit_client 2.8.1 have a video processor seam at all

Yes, a seam exists, and it has existed since `livekit_client` 2.3.5 ("feat: add TrackProcessor support. (#657)", per that version's CHANGELOG entry).
But it is a lifecycle interface, not a frame-transform callback, and it never hands Dart code a decoded frame on any platform.

`lib/src/track/processor.dart:15-28` (livekit_client 2.8.1):

```
abstract class TrackProcessor<T extends ProcessorOptions> {
  String get name;
  Future<void> init(T options);
  Future<void> restart(T options);
  Future<void> destroy();
  Future<void> onPublish(Room room);
  Future<void> onUnpublish();
  MediaStreamTrack? get processedTrack;
}
```

`ProcessorOptions` (same file, lines 6-13) carries only a `kind` and the input `track` (a `flutter_webrtc` `MediaStreamTrack`), and the native/web variants (`processor_native.dart:6-16`, `processor_web.dart:7-22`) add nothing beyond an audio element/context on web.
There is no `VideoFrame` type anywhere in this call shape.
A `TrackProcessor` is handed the raw input track and is expected to produce its *own* `processedTrack` (another `MediaStreamTrack`) by whatever means it can find; the interface says nothing about how.

The wiring into publishing is real: `CameraCaptureOptions` (which extends `VideoCaptureOptions`) carries a `processor` field (`lib/src/track/options.dart:231-232`, threaded through the constructor at line 65 and `copyWith` at line 129), `LocalVideoTrack`'s track creation applies it (`lib/src/track/local/video.dart:202-203`, `await track.setProcessor(options.processor)`), and `LocalTrack.setProcessor` (`lib/src/track/local/local.dart:338-361`) calls `init` on it and swaps in `processedTrack` if one comes back.
So `room.localParticipant?.setCameraEnabled(true, cameraCaptureOptions: CameraCaptureOptions(processor: myProcessor))` is a real, reachable call in this exact pinned version.
What is missing is anything to put inside `myProcessor` that can see a frame from Dart.

**A real bug in this path, and it predates our pinned version being safe from it.**
`setProcessor` used to build an `AudioProcessorOptions` regardless of the track's actual kind, so a video processor was handed the wrong options type.
That was fixed in `livekit_client` 2.6.5 ("Fixed: setProcessor() now uses VideoProcessorOptions for video tracks instead of AudioProcessorOptions"), which sits *before* our pinned 2.8.1 in the release order (2.6.5 -> 2.7.0 -> 2.8.0 -> 2.8.1 -> 2.9.0, the current latest as of this writing), confirmed by fetching the SDK's own `CHANGELOG.md` from `github.com/livekit/client-sdk-flutter`.
So this specific bug does not affect us.
It is still worth recording because of what closing it revealed: [issue #880](https://github.com/livekit/client-sdk-flutter/issues/880) tracked it, was closed 2026-03-04 by [PR #1014](https://github.com/livekit/client-sdk-flutter/pull/1014), and the issue's own comment thread (read via `gh api repos/livekit/client-sdk-flutter/issues/880/comments`) shows real developers, as late as January 2026, still not able to get a working blur processor out of this API even after the type fix.
One commenter's friend got it working only by forking the SDK, removing `LocalVideoTrack`'s private constructors, and wrapping the underlying stream using a third-party native SDK (see the "alternatives" section below) - not by using `TrackProcessor` as documented.

**Per-frame native hooks exist underneath this interface, but none of them reach Dart.**
Searching the whole `flutter_webrtc` 1.4.0 source tree for `VideoFrame`, `VideoProcessor`, `VideoSink` and `addProcessing`/`addProcessor` turns up:

- **iOS and macOS (darwin).** A real native seam: `VideoProcessingAdapter` (`ios/Classes/VideoProcessingAdapter.h`, mirrored in `macos/Classes/` and `common/darwin/Classes/`) defines an `ExternalVideoProcessingDelegate` protocol with one method, `onFrame:` returning a transformed `RTCVideoFrame`, and `LocalVideoTrack.addProcessing:`/`removeProcessing:` (`common/darwin/Classes/LocalVideoTrack.m:39-44`) registers one against it. This is genuine per-frame ObjC access. It has no Dart binding at all: grepping every native `.m` file for callers of `addProcessing:` finds only the plugin's own internal use for the desktop-capturer path (`FlutterRTCDesktopCapturer.m:30`) and media-stream creation (`FlutterRTCMediaStream.m:489`), never a `MethodChannel` handler that would let Dart register one.
- **Android.** The same shape in Kotlin/Java: `com.cloudwebrtc.webrtc.video.LocalVideoTrack` (`android/src/main/java/com/cloudwebrtc/webrtc/video/LocalVideoTrack.java`) implements `org.webrtc.VideoProcessor` directly and exposes `addProcessor(ExternalVideoFrameProcessing)`, handed a real `org.webrtc.VideoFrame` per call (lines 17-22, 55-63). Also native-only; nothing in the Dart layer calls it.
- **Linux and Windows.** Nothing. Grepping `common/cpp`, `linux/`, `windows/` and `elinux/` for the same terms returns zero matches. The only per-frame native code shared by these platforms is `flutter_frame_capturer.cc` (a single-shot screenshot, the same shape as the Dart-reachable `captureFrame()` described below) and `flutter_video_renderer.cc` (decode-for-display only, one-way, with no path back into the encode pipeline). There is no video-frame hook of any kind to build on here, native or otherwise.
- **Web.** Chromium browsers have a genuine per-frame primitive of their own, the Insertable Streams / Breakout Box API (`MediaStreamTrackProcessor`, `MediaStreamTrackGenerator`, the browser's own `VideoFrame`), which is exactly what LiveKit's official JavaScript SDK uses for its shipped, working blur (`livekit/track-processors-js`). `flutter_webrtc`'s web layer does not wire any of it: grepping `lib/src/web/` for those names finds nothing, and the one `VideoFrame`-adjacent reference (`rtc_video_view_impl.dart:64,208-231`) is `requestVideoFrameCallback` used purely for renderer paint timing, never handed to application code.

Also worth naming precisely because it changes the read of "missing": the one Dart-reachable, cross-platform frame-adjacent call that does exist, `MediaStreamTrack.captureFrame()` (`lib/src/native/media_stream_track_impl.dart:87-97`), round-trips a single frame to a PNG file on disk per call.
It is built for a one-off snapshot feature, not a 30-times-a-second pipeline, and its own implementation (write to disk, read the file back into Dart) makes clear it was never meant to be one.

## 2. If the seam is incomplete, what are the alternatives, and what would each cost

**Capturing to a texture and re-publishing from Dart: not viable, because the primitive it needs does not exist either.**
The obvious "route around it" idea is to render the camera preview to a Flutter texture, run segmentation and blur compositing on the pixels in Dart, and republish the result as a new capture source.
That needs a way to construct a `MediaStreamTrack` from raw frames pushed in from Dart, and `flutter_webrtc`'s public API has no such thing: `createLocalMediaStream` (`lib/src/native/factory_impl.dart:23-26`) creates an empty stream with no track, and there is no `addVideoTrackFromFrames` or equivalent anywhere in the package. This option is not merely expensive, it is blocked outright by an absent primitive, on every platform.
Even if it existed, a platform-channel round trip for every 720p frame, encoded and decoded each way, would very likely blow the frame budget on serialization and copying alone before a single pixel of segmentation ran - which is also the strongest argument for why the real native hooks found above (Darwin, Android) are native-to-native and were never designed to cross into Dart at all. That is a property of doing this correctly, not an oversight somebody forgot to fix.

**A native platform-channel processor, one per platform: the only real path, and the cost is per platform, not shared.**
- **iOS/macOS**: plug into the existing `VideoProcessingAdapter`/`ExternalVideoProcessingDelegate` hook directly (new native Swift/ObjC code calling into `LocalVideoTrack.addProcessing:`), run Apple's own Vision-framework person segmentation (see below) inside `onFrame:`, composite the blur, hand back an `RTCVideoFrame`. This is genuinely buildable today with no new third-party dependency, and it is the same shape of work as this project's existing `BroadcastBridge` Swift bridge for iOS screen share (see `CLAUDE.md`'s "The one-flag iOS screen share fix" entry): a `// ignore` -style reach past the plugin's public surface into its own native internals, exercised and tested the same way.
- **Android**: plug into `LocalVideoTrack.addProcessor` (Kotlin), run a bundled TFLite segmentation model natively (see below), composite, return the frame. Buildable, but the model itself is the blocker (see the frame-budget section).
- **Linux/Windows**: there is no hook to plug into. This would mean either a genuine upstream contribution to `flutter_webrtc`'s shared `common/cpp` layer (a real, non-trivial patch to a project this repo does not control), or bypassing `flutter_webrtc`'s camera capture path entirely with a separate custom capturer, which is a much larger undertaking than "add a processor."
- **Web**: hand-written `dart:js_interop` reaching past `flutter_webrtc`'s Dart layer to use `MediaStreamTrackProcessor`/`MediaStreamTrackGenerator` directly, feeding a JS-side segmentation model (TensorFlow.js's own selfie-segmentation model, or a hand-rolled call into `@mediapipe/selfie_segmentation`). Buildable, and precedented in this codebase (`BroadcastBridge`'s `implementation_imports` reach, and the project's own web-`paste`-event work for clipboard images), but it is custom interop code with no plugin support, same as every other platform here.

**An upstream contribution:** for Linux/Windows specifically, this is the only route that does not amount to replacing `flutter_webrtc`'s own capture pipeline, and it is squarely out of this project's hands on any timeline it controls.

## 3. What actually runs the segmentation, surveyed per platform

No single package covers all six platforms, and the two most commonly reached-for options cover the fewest of them.

| Option | Linux | Windows | macOS | iOS | Android | Web | Model size / licence | Native dependency |
|---|---|---|---|---|---|---|---|---|
| Google ML Kit Selfie Segmentation (`google_mlkit_selfie_segmentation`, pub.dev 0.11.0) | No | No | No | Yes | Yes | No | Wrapper is MIT; underlying ML Kit model is Google's own on-device SDK under Google's terms, not open source | Google Play Services on Android; ML Kit's native binaries on both |
| Raw MediaPipe `selfie_segmenter.tflite` via `tflite_flutter` (pub.dev 0.12.1) | Yes, with manual native build | Yes, with manual native build | Yes, with manual native build | Yes, automatic | Yes, automatic | No | Model: Apache 2.0 (`google-ai-edge/mediapipe`), ~450KB, 106K params, 256x256x3 input / 256x256x1 output (general model); wrapper: Apache 2.0 | A prebuilt TFLite C library, auto-fetched on Android/iOS; on Linux/macOS/Windows the developer must build `libtensorflowlite_c` themselves via Bazel or CMake and wire it into the platform's `CMakeLists.txt`/Xcode project by hand |
| Apple Vision framework, `VNGeneratePersonSegmentationRequest` (iOS 15+/macOS 12+) | No | No | Yes | Yes | No | n/a | First-party, no bundled model, no extra licence | None; ships with the OS, runs on the Neural Engine |
| A dedicated Flutter/MediaPipe segmentation plugin | - | - | - | - | - | - | - | No mature one exists: `flutter_mediapipe` wraps face mesh, a ThinkSys plugin wraps pose detection, `face_detection_tflite` bundles a raw segmentation `.tflite` model directly rather than going through MediaPipe's own runtime. None of these is a drop-in selfie-segmentation package. |

Two things worth being explicit about because this project has been burned by assumed platform support before (`Helper.setVolume` working on three of six platforms, `useiOSBroadcastExtension` looking right and failing on a real device):

- **I did not attempt to build `tflite_flutter`'s desktop path in this environment.** The README's own description of Linux/Windows/macOS setup (build your own native binary, hand-place it, edit the platform build files) is a genuinely different kind of "supported" than Android/iOS's automatic download, and pub.dev's platform badges do not distinguish the two. Whether it actually links on this project's own Fedora KDE Wayland target is unverified.
- **The TFLite ecosystem's own maintainers point away from `tflite_flutter` for this.** Its README currently states its image-processing helper library is deprecated and recommends "MediaPipe Flutter" instead - which, per the survey above, does not exist as a maintained package covering selfie segmentation. There is no currently-supported, well-trodden path here; whichever route is taken, this project would be writing and maintaining the pre/post-processing (crop, resize, normalize, threshold or matte the mask, feather edges, composite the blur) itself, on every platform except where Apple's Vision framework does that work already.

## 4. Frame budget

720p30 gives 33.3ms per frame, shared with video encode and every other camera-path cost; segmentation is not the only thing competing for that budget, just the new one.

The clearest primary-sourced number comes from [google-ai-edge/mediapipe issue #5954](https://github.com/google-ai-edge/mediapipe/issues/5954), filed by a real developer against MediaPipe Tasks 0.10.14 running the general `selfie_segmenter.tflite` model (the same model named in the table above) on a **Google Pixel 9** - a current-generation flagship device, not a budget or mid-range phone:

- CPU delegate, livestream mode: **90+ ms on average.**
- Downsizing the input 60% brought that to roughly 60ms, "but this also gives unacceptably poor segmentation" in the reporter's own words.
- The DeepLabV3 alternative model measured worse, 200+ ms.
- GPU delegate: "inference completely fails or becomes extremely slow, or on certain devices, appears to crash" - the fast path is reported broken for this exact task on Android, forcing the CPU fallback above.
- The same model in a browser, on the same class of hardware, hits under 3ms with WebGL/GPU and about 120ms on CPU alone - so the model is capable of real-time on a GPU path; Android's GPU delegate specifically is where this falls down, per this report.

90ms alone is roughly 2.7x the entire 33ms frame budget, on a flagship phone, before any encode, colour conversion, or blur compositing cost is spent, and with the one path that would fit the budget (GPU) reported non-functional for this exact model and platform.
A genuinely mid-range Android phone should be expected to do no better than this, and plausibly worse.

I could not find an equivalent primary-sourced millisecond figure for the Apple Vision-framework path.
Apple's own documentation says operations run "in milliseconds" on the Neural Engine and describes the same underlying technology as powering Portrait mode and being reusable statefully across a live camera stream, which is a real and specific claim, but not a number.
One developer forum thread (found via search, not independently verified here) reports a lagging video feed from `VNGeneratePersonSegmentationRequest` in a macOS camera-extension integration, which is worth treating as a sign that even the fastest available path here is not necessarily friction-free in every real integration, rather than as proof it fails.
This is an explicit gap: the Apple path is the most promising of everything surveyed, and it is also the one where I have no measured number, only a vendor claim and one anecdotal counter-report.

One number found by an earlier web search and not used above: a claim of "0.733ms on a Galaxy S23 Ultra" for the same model.
I could not trace this to a primary source (no GitHub issue, benchmark repository, or vendor page corroborated it), it does not square with the Pixel 9 measurement above from the same model family, and repeating it here without a source would be exactly the kind of plausible-sounding number this project has been burned by before. Recorded as discarded rather than silently dropped.

## 5. Recommendation

**Build a reduced version: ship blur wherever a real native path exists, and gate the camera toggle itself off where it does not, rather than either shipping raw camera everywhere immediately or blocking all camera work on a seam that does not exist uniformly today.**

The reasoning, not just the verdict:

- **"Build it" as a uniform, day-one, six-platform feature is not realistically achievable right now.** No package covers more than five of the six platforms even in principle (`tflite_flutter`), and that fifth-platform coverage on Linux/Windows/macOS is a manual native-build burden this project has not attempted, layered on top of a model that, per a primary source, does not fit a 33ms frame budget even on a flagship Android phone with its fast GPU path reportedly broken. Linux and Windows additionally have no native per-frame hook of any kind in the WebRTC layer this project depends on - not incomplete, absent - so parity there is upstream work outside this project's control, not an integration task.
- **"Do not ship camera until an upstream seam exists" concedes too much, because Apple's platforms do not need one.** iOS and macOS already have both a real native per-frame hook (`VideoProcessingAdapter`) and a real first-party, no-dependency segmentation model (Vision framework, Neural Engine-accelerated) that this codebase has direct precedent for reaching (the `BroadcastBridge` pattern). Holding the entire camera feature hostage to Linux and Windows, which have nothing to build on at all, would delay the platforms where this is genuinely close to the owner's stated day-one bar for no clear reason.
- **So the middle path is the honest one: build native blur where a real seam and a fast-enough model both exist (iOS/macOS first), and treat every other platform as explicitly reduced or absent rather than pretending parity.** Android has the native hook but not (yet, on this evidence) a model that clears the frame budget reliably; that is worth a real measurement pass on actual target devices before committing, not a guess either way. Linux, Windows and web need meaningfully new engineering (upstream contribution, a from-scratch capturer, or hand-written JS interop respectively) that should not block the platforms already in reach.
- **Whatever ships, the UI has to say what it is doing per platform, not silently do less.** This project has already paid once for camera/voice features that quietly worked on three of six platforms and not the others with no signal to the user (`Helper.setVolume`, and Linux/web screen-share support) - CLAUDE.md records both. A camera toggle that blurs on iOS and does not on Android or desktop needs to say so, the same way `supportsParticipantVolume` already gates the per-participant volume slider on platform capability rather than showing a control that silently does nothing.
- **Do not let "reduce resolution to save frame budget" stand in for a real fix on Android.** The one real-world data point for this (the mediapipe issue above) tried it, got roughly 60ms instead of 90ms, still nowhere near the 33ms budget, and called the resulting segmentation quality unacceptable. If Android is pursued, it needs its own measurement on real target hardware before any budget claim is made, not an assumption carried over from this spike.

## What this spike did not settle

- Whether `tflite_flutter`'s Linux/macOS/Windows native build actually links on this project's own Fedora KDE Wayland target, or on Windows/macOS CI runners. Untested here.
- A measured inference number for Apple's Vision framework on a real iPhone. Only a vendor "milliseconds" claim and one anecdotal report of lag in an unrelated integration.
- Whether Android's GPU delegate failure in the cited issue is specific to MediaPipe Tasks 0.10.14 or also affects a raw `tflite_flutter` integration bypassing MediaPipe Tasks entirely; the underlying TFLite GPU delegate is shared, but this was not independently confirmed.
- The actual compositing cost (alpha matte plus Gaussian blur over a 720p frame) on top of segmentation, on any platform. Everything measured above is the segmentation pass alone.
- Licensing terms for Google ML Kit's on-device selfie segmentation model specifically, beyond "not open source, Google's own terms" - not read in full here since ML Kit is ruled out on coverage grounds (Android/iOS only) before licence would matter.
