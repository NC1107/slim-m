// SPDX-License-Identifier: Apache-2.0
/// What the host app knows about iOS screen capture that Dart cannot see.
///
/// iOS is the one platform where a screen share is not something the app does.
/// An app may only capture its own window; everything else is captured by a
/// separate process, a ReplayKit broadcast upload extension, which the system
/// starts on the user's say-so and which hands frames back through a socket in
/// a shared App Group container.
///
/// Two consequences shape this file. Starting a share is a request, not an
/// action, so "the call returned" does not mean anybody is seeing a screen.
/// And a build can be missing the extension entirely, in which case the
/// request can never succeed, which is worth knowing before asking rather
/// than after waiting.
library;

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// The seam. The default implementation talks to the app's iOS host; a test
/// supplies its own, which is the only way any of this is exercisable off a
/// device.
abstract class BroadcastBridge {
  /// Whether capture on this platform goes through a broadcast extension at
  /// all. False everywhere but iOS, where the rest of this is moot.
  bool get usesBroadcastExtension;

  /// Whether this build can actually broadcast: the extension named in
  /// Info.plist exists, and the App Group container it shares with the app is
  /// reachable. False means the share control cannot work in this build, no
  /// matter how long anybody waits.
  Future<bool> isAvailable();

  /// Ends a running broadcast. Nothing else can: LiveKit unpublishing the
  /// track leaves ReplayKit recording, red status bar and all.
  Future<void> requestStop();
}

/// Answers over a method channel the iOS host registers in
/// `BroadcastChannel.swift`.
///
/// The broadcast upload extension now exists (target `BroadcastExtension`, its
/// App Group and profile provisioned), so on a correctly signed build
/// [isAvailable] answers true and the share publishes through LiveKit's
/// `BroadcastManager` path - see `VoiceSession.captureOptionsFor` for the flag
/// that keeps that path from double-starting. A build still missing the
/// extension, or one where the App
/// Group entitlement did not make it into the signature, answers false here
/// and the share control reports [ScreenShareOutcome.unsupported] rather than
/// lighting up over a share nobody could see.
class MethodChannelBroadcastBridge implements BroadcastBridge {
  const MethodChannelBroadcastBridge();

  static const channel = MethodChannel('top.npcserver.slimm/broadcast');

  @override
  bool get usesBroadcastExtension => lk.lkPlatformIs(lk.PlatformType.iOS);

  /// A missing handler answers false rather than throwing: an app build
  /// without this channel has no extension either, which is the same answer.
  @override
  Future<bool> isAvailable() async {
    if (!usesBroadcastExtension) return true;
    try {
      return await channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> requestStop() async {
    if (!usesBroadcastExtension) return;
    try {
      await channel.invokeMethod<void>('requestStop');
    } on PlatformException {
      // Nothing to stop, or no host to ask. Either way the share is over as
      // far as this side is concerned.
    } on MissingPluginException {
      // As above.
    }
  }
}
