// SPDX-License-Identifier: Apache-2.0
/// Bridges the APNs device token from native iOS code.
///
/// Registration is asynchronous and native-driven: the token, or a failure,
/// can land before Dart ever asks (a fast relaunch) or long after (the user
/// takes a while on the permission prompt, or never answers). Caching
/// whichever arrives first on the native side, and replaying it here, means
/// neither ordering loses the result. See `AppDelegate.swift` for the other
/// half of this channel.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'host_platform.dart';

const _channelName = 'top.npcserver.slimm/push';

/// The lowercase, unseparated hex APNs and the push relay expect for a device
/// token. `AppDelegate.swift` performs the equivalent conversion on the actual
/// token bytes (deliberately not `Data.description`, which iOS now redacts to
/// something like "32 bytes"); this pure copy exists so the wire format has a
/// test that can run without Xcode, which this project's iOS side otherwise
/// cannot be.
String hexEncodeToken(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// What asking the native side for a device token came back with.
///
/// Kept distinct from a plain nullable [String] because a caller reporting
/// push status honestly needs to say which of these happened: those are three
/// different stories to tell a tester ("this device cannot", "still
/// waiting", "it tried and failed"), not one flat "no token".
sealed class ApnsTokenResult {
  const ApnsTokenResult();
}

/// This platform has no push channel: nothing native answers it.
class ApnsUnsupported extends ApnsTokenResult {
  const ApnsUnsupported();
}

/// A usable device token.
class ApnsTokenReady extends ApnsTokenResult {
  const ApnsTokenReady(this.token);
  final String token;
}

/// Neither a token nor an error arrived within the wait: the permission
/// prompt has not been answered yet, or the round trip is just slow.
class ApnsTokenPending extends ApnsTokenResult {
  const ApnsTokenPending();
}

/// The native side reported the device token request itself failed.
/// [reason] is `Error.localizedDescription` from `AppDelegate.swift`, worth
/// showing verbatim: it is the one piece of native diagnosis that reaches
/// Dart at all.
class ApnsRegistrationFailed extends ApnsTokenResult {
  const ApnsRegistrationFailed(this.reason);
  final String reason;
}

/// Fetches the APNs device token registered by native code, as the lowercase
/// hex string APNs and the push relay expect.
///
/// A clean no-op everywhere but iOS: nothing on Linux desktop, Android or the
/// web answers this channel (Android registers through [FcmTokenChannel]
/// instead, and a browser has no APNs at all), so [fetch] reports
/// [ApnsUnsupported] there rather than touching it. Push is a nice-to-have; it
/// must never be the reason the app fails to start or sign in.
class ApnsTokenChannel {
  ApnsTokenChannel({MethodChannel? channel, bool? isIOS})
      : _channel = channel ?? const MethodChannel(_channelName),
        _isIOS = isIOS ?? isIOSHost {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final bool _isIOS;
  Completer<String?>? _pending;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        _complete(call.arguments as String?);
      case 'onRegistrationError':
        _complete(null);
    }
  }

  void _complete(String? token) {
    final pending = _pending;
    _pending = null;
    pending?.complete(token);
  }

  /// The device token, or null if this is not iOS, the user has not yet
  /// resolved the permission prompt within [timeout], or registration failed.
  /// A thin, backward-compatible view of [fetch] for callers that only care
  /// whether a token exists, not why one is missing.
  Future<String?> token(
      {Duration timeout = const Duration(seconds: 10)}) async {
    final result = await fetch(timeout: timeout);
    return switch (result) {
      ApnsTokenReady(:final token) => token,
      _ => null,
    };
  }

  /// The device token, distinguishing every way one can be missing so a
  /// caller can report push status honestly instead of a flat null.
  ///
  /// The completer is installed before the first probe, not after it. Each
  /// probe is an async round trip to the native side, and the token can land in
  /// the gap between them; with nothing waiting, that delivery is dropped and
  /// the wait then times out having already been handed the answer. Since a
  /// dropped token means the device registers for push and never tells the
  /// server, it fails as silence rather than an error.
  Future<ApnsTokenResult> fetch(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (!_isIOS) return const ApnsUnsupported();

    // Installed before the first probe so a token landing between probes is
    // not dropped. See the doc comment above.
    final pending = _pending ??= Completer<String?>();
    try {
      final cached = await _channel.invokeMethod<String>('getToken');
      if (cached != null) {
        _pending = null;
        return ApnsTokenReady(cached);
      }
      if (pending.isCompleted) return _resultOf(await pending.future);

      final error = await _channel.invokeMethod<String>('getRegistrationError');
      if (pending.isCompleted) return _resultOf(await pending.future);
      if (error != null) {
        _pending = null;
        return ApnsRegistrationFailed(error);
      }

      // Neither has arrived; wait for whichever the native side delivers first,
      // capped so an unanswered permission prompt cannot hang registration.
      final token = await pending.future.timeout(timeout, onTimeout: () {
        _pending = null;
        return null;
      });
      return _resultOf(token);
    } on MissingPluginException {
      _pending = null;
      return const ApnsTokenPending();
    } on PlatformException catch (e) {
      _pending = null;
      return ApnsRegistrationFailed(e.message ?? e.code);
    }
  }

  ApnsTokenResult _resultOf(String? token) =>
      token == null ? const ApnsTokenPending() : ApnsTokenReady(token);
}
