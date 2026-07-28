// SPDX-License-Identifier: Apache-2.0
/// The two things a caller has to say and be told about a screen share: how
/// it may be published, and what asking actually did.
///
/// Split out of `voice_session.dart` because neither depends on a session or
/// on LiveKit, and both are read by the UI far from any call.
library;

/// How a screen share is published.
///
/// Ceilings rather than preferences: an unbounded share on a 4K monitor will
/// happily saturate a home upload and starve the audio it is supposed to
/// accompany, and audio degrading is far more noticeable than a slightly softer
/// screen.
enum ScreenShareQuality {
  /// Anything moving. Lower resolution, higher frame rate.
  smooth(width: 1280, height: 720, fps: 60, maxBitrate: 2500000),

  /// The default. Balanced for a desktop with some motion.
  balanced(width: 1920, height: 1080, fps: 30, maxBitrate: 2400000),

  /// Reading code. Higher resolution, lower frame rate.
  crisp(width: 2560, height: 1440, fps: 15, maxBitrate: 3000000);

  const ScreenShareQuality({
    required this.width,
    required this.height,
    required this.fps,
    required this.maxBitrate,
  });

  final int width;
  final int height;
  final int fps;
  final int maxBitrate;
}

/// A screen the OS will let this app capture.
///
/// Screens only, never windows. Enumerating windows through libwebrtc's
/// desktop capturer segfaults the process on Fedora Wayland (SIGSEGV, exit
/// 139, reproduced 2026-07-27), and a native crash is not catchable from Dart.
class ScreenShareSource {
  const ScreenShareSource({required this.id, required this.name});

  /// Opaque to us, and the only thing `getDisplayMedia` matches on.
  final String id;

  /// The capturer's own label, 'Screen 1' and up on Linux.
  final String name;
}

/// What asking to share a screen actually did.
///
/// Deliberately not a bool. On iOS "the request went through" and "somebody
/// can see a screen" are two different moments with a user in between: capture
/// runs in a broadcast upload extension that only the system picker can start.
/// A bool has to pick one of those to mean, and either choice makes the button
/// lie in one direction. See [BroadcastBridge] for why the platform is like
/// this.
enum ScreenShareOutcome {
  /// A screen track is published. Everyone in the call can see it now.
  started,

  /// The request went through, nothing is published yet, and it is up to the
  /// user: iOS has been asked to show its broadcast picker. If they dismiss
  /// it, nothing further happens and no failure is reported anywhere.
  pendingBroadcast,

  /// This build cannot share a screen at all, because it has no working
  /// broadcast extension. Asking again will not help.
  unsupported,

  /// Sharing is off, as asked.
  stopped,

  /// The request failed outright. [VoiceSession.lastError] says how.
  failed,
}
