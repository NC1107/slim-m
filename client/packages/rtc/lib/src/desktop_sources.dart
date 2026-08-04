// SPDX-License-Identifier: Apache-2.0
/// Enumerating what a desktop will let this app capture.
///
/// On desktop this is not optional and not a nicety. `getDisplayMedia` matches
/// the requested id against a list the native plugin only fills in when
/// `getSources` is called, so asking to share without enumerating first fails
/// with `source not found!` no matter what else is right. That was the whole
/// Fedora screen-share bug.
library;

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'screen_share.dart';

/// The seam. The default implementation talks to libwebrtc's desktop
/// capturer; a test supplies its own.
abstract class DesktopSources {
  /// Whether a share on this platform must name a source. False on mobile,
  /// where the OS owns the choice and there is nothing to enumerate.
  bool get required;

  /// Whether presenting several enumerated sources for a person to choose
  /// between is a real choice, worth its own picker.
  ///
  /// False on Linux. `list` still has to run there (see the class doc), but
  /// on a Wayland session the real choice happens in xdg-desktop-portal's
  /// own picker, which negotiates the capture independently of whatever id
  /// this app hands it - asking here too is a second dialog for one choice,
  /// which is what PR #348's own re-entrancy fix left open as an unverified
  /// native-side possibility, and what "still two popups" confirmed. On X11
  /// this branch was never reachable anyway: enumerating has only ever
  /// returned the one merged screen. macOS and Windows have no such native
  /// picker of their own, so this app's sheet stays their only one.
  bool get sourcePickerUseful;

  Future<List<ScreenShareSource>> list();
}

class WebrtcDesktopSources implements DesktopSources {
  const WebrtcDesktopSources();

  @override
  bool get required => lk.lkPlatformIsDesktop();

  @override
  bool get sourcePickerUseful => !lk.lkPlatformIs(lk.PlatformType.linux);

  /// [webrtc.SourceType.Window] is deliberately never requested: see
  /// [ScreenShareSource] for the crash that causes.
  @override
  Future<List<ScreenShareSource>> list() async {
    if (!required) return const [];
    final sources = await webrtc.desktopCapturer.getSources(
      types: [webrtc.SourceType.Screen],
    );
    return [
      for (final source in sources)
        ScreenShareSource(id: source.id, name: source.name),
    ];
  }
}
