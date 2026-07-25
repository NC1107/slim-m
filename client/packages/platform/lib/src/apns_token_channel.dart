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
import 'dart:io';

import 'package:flutter/services.dart';

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

/// Fetches the APNs device token registered by native code, as the lowercase
/// hex string APNs and the push relay expect.
///
/// A clean no-op everywhere but iOS: nothing on Linux desktop or (for now)
/// Android answers this channel, so [token] returns null there rather than
/// touching it, and a denied or failed registration on iOS itself also comes
/// back as null rather than an exception. Push is a nice-to-have; it must
/// never be the reason the app fails to start or sign in.
class ApnsTokenChannel {
  ApnsTokenChannel({MethodChannel? channel, bool? isIOS})
      : _channel = channel ?? const MethodChannel(_channelName),
        _isIOS = isIOS ?? Platform.isIOS {
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
  Future<String?> token(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (!_isIOS) return null;

    // The sink is installed before the first probe, not after it. Each probe is
    // an async round trip to the native side, and the token can land in the gap
    // between them; with no completer waiting, that delivery is dropped and the
    // wait below then times out having already been handed the answer. Since a
    // dropped token means the device registers for push and never tells the
    // server, it fails as silence rather than an error.
    final pending = _pending ??= Completer<String?>();
    try {
      final cached = await _channel.invokeMethod<String>('getToken');
      if (cached != null) {
        _pending = null;
        return cached;
      }
      if (pending.isCompleted) return pending.future;

      final error = await _channel.invokeMethod<String>('getRegistrationError');
      if (pending.isCompleted) return pending.future;
      if (error != null) {
        _pending = null;
        return null;
      }

      // Neither has arrived yet; wait for whichever the native side delivers
      // first, capped so a permission prompt nobody answers cannot hang
      // registration forever.
      return await pending.future.timeout(timeout, onTimeout: () {
        _pending = null;
        return null;
      });
    } on MissingPluginException {
      _pending = null;
      return null;
    } on PlatformException {
      _pending = null;
      return null;
    }
  }
}
