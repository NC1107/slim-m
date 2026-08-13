// SPDX-License-Identifier: Apache-2.0
/// Whether this platform can publish audio alongside a shared screen, and the
/// honest answer per platform, traced through livekit_client 2.10.0 and the
/// pinned flutter_webrtc 1.6.0 rather than assumed.
///
/// [lk.ScreenShareCaptureOptions.captureScreenAudio] exists on every
/// platform, but it is not the flag that actually gates anything.
/// `LocalParticipant.setSourceEnabled` (`participant/local.dart`) only takes
/// the `createScreenShareTracksWithAudio` path - the one that extracts and
/// publishes an audio track from the captured stream - when its own
/// **top-level** `captureScreenAudio` parameter is true; the options field is
/// only ever consulted by force-copying it to match that parameter, never the
/// other way round. So this package threads a plain `includeAudio` bool
/// through to that top-level parameter rather than setting the options
/// field, which by itself would change nothing.
///
/// **Web (Chromium family) works, source-verified.** `dart_webrtc`'s
/// `MediaDevicesWeb.getDisplayMedia` (`mediadevices_impl.dart`) `jsify()`s the
/// whole constraints map, `audio` included, straight into the browser's own
/// `navigator.mediaDevices.getDisplayMedia`, exactly the shape the W3C
/// Screen Capture spec defines. Whether a given browser actually offers tab
/// or system audio in its picker is that browser's own business, not this
/// app's: Chromium-family browsers support it, Firefox and Safari do not
/// honour the `audio` constraint there at all. Either way the failure mode is
/// silent degradation to video-only, never an error - see the platform-split
/// note below - so the toggle is safe to offer on every web build.
///
/// **Linux works, conditionally, and the condition is a build-time flag this
/// package cannot see at runtime.** `flutter_webrtc`'s own
/// `linux/pulse_loopback_capturer.cc` streams the default sink's PulseAudio
/// monitor into the captured track, gated at compile time on
/// `HAVE_LIBPULSE`, which `linux/CMakeLists.txt` only defines when
/// `pkg_check_modules` finds `libpulse` and `libpulse-simple` on the build
/// host. `docs/os_backlog/linux_backlog.md` records this build dependency
/// being added to this project's own CI so a shipped Linux build actually
/// carries it; before that, `CreateLoopbackCapturer` silently returns
/// `nullptr` and a Linux share simply never gets an audio track, no error at
/// any layer.
///
/// **macOS and iOS do not, and cannot through this seam at all.**
/// `common/darwin/Classes/FlutterRTCDesktopCapturer.m`'s `getDisplayMedia`
/// hardcodes `'audio': false` and returns an empty `audioTracks` list
/// unconditionally - there is no code path there that ever looks at the
/// `audio` constraint. iOS's screen share does not run through this call at
/// all in the first place: it is `BroadcastManager`'s ReplayKit broadcast
/// extension, whose own audio (system and in-app) arrives through
/// `RPBroadcastSampleHandler`'s separate audio sample-buffer callbacks, a
/// mechanism this package's Dart capture-options seam has no reach into.
/// Real app-audio-in-broadcast is native Swift work in the extension itself,
/// not a flag here.
///
/// **Android does not.** `GetUserMediaImpl.java`'s `getDisplayMedia` builds
/// its `MediaProjection`-backed video capturer and hands back a hardcoded
/// empty `audioTracks` array; nothing in that file touches Android's own
/// `AudioPlaybackCapture` API (available since API 29).
///
/// **Windows is unbuilt, not unsupported.** `flutter_webrtc`'s
/// `windows/application_loopback_capturer.cc` implements the same
/// `LoopbackCapturer` interface Linux does, over WASAPI, and would be reached
/// by this same seam - but this project ships no Windows client target at
/// all yet (`docs/os_backlog/windows_backlog.md`), so there is nothing to gate
/// here.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Whether the platform this app is running on can add a real audio track to
/// a screen share through this package's capture seam.
///
/// False does not mean "unimplemented here" for every platform: on Linux it
/// means "reachable, contingent on a build-time flag no Dart call can
/// observe," and the toggle is still offered there because the degradation
/// on a build lacking it is silent and harmless (a video-only share, exactly
/// what publishes today). On macOS, iOS, Android and Windows it means the
/// underlying platform capture genuinely has no such path, so the control is
/// absent rather than present-and-inert, the same rule
/// `supportsParticipantVolume` (`audio_gain.dart`) already established for
/// call volume.
///
/// [platform] is [ScreenShareControl.captureOptionsFor]'s own `isIOS` seam,
/// the same shape: null (the production default) asks the real platform, and
/// a test supplies its own so a hardcoded-true mutation is actually
/// reachable. This project's own CI and local `flutter test` both run on
/// Linux, which is itself one of the true platforms, so a plain comparison
/// against the real `lk.lkPlatform()` would let that exact mutation through
/// silently - traced and fixed rather than assumed benign.
bool supportsScreenShareAudio({@visibleForTesting lk.PlatformType? platform}) {
  final onPlatform = platform ?? lk.lkPlatform();
  return onPlatform == lk.PlatformType.web ||
      onPlatform == lk.PlatformType.linux;
}
