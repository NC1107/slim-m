// SPDX-License-Identifier: Apache-2.0
/// Registers this device for push and keeps the server's foreground guess
/// current.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_platform/platform.dart';

import 'providers.dart';

/// The native bridge for this device's APNs token. A provider, rather than a
/// field [PushController] constructs itself, so a test can substitute one
/// that does not depend on the test runner actually being iOS.
final apnsTokenChannelProvider =
    Provider<ApnsTokenChannel>((ref) => ApnsTokenChannel());

/// Registers this device's push token and encryption public key, and reports
/// foreground/background transitions once registered.
///
/// Runs after sign-in (it needs an access token) and again on every later
/// session change, so a refreshed or re-established session keeps the
/// registration current without every call site needing to remember to ask.
/// Every step is best-effort: a user who denied notifications, or is running
/// the Linux desktop build where there is no APNs at all, must still get a
/// fully working app. There is no platform check here beyond that: the token
/// channel itself is the no-op on anything but iOS, so nothing below it ever
/// runs on another platform.
class PushController with WidgetsBindingObserver {
  PushController(this._ref) {
    _sessionSubscription = _ref.read(sessionProvider).changes.listen((tokens) {
      if (tokens != null) unawaited(register());
    });
  }

  final Ref _ref;
  late final StreamSubscription<TokenPair?> _sessionSubscription;
  bool _observingLifecycle = false;

  /// Fetches, or reuses, this device's push keypair and token, and tells the
  /// server about them. A no-op without a session, and swallows every failure
  /// past that point rather than letting a push problem become an app problem.
  Future<void> register() async {
    if (!_ref.read(sessionProvider).isSignedIn) return;

    try {
      final token = await _ref.read(apnsTokenChannelProvider).token();
      if (token == null) return;

      final keyStore = _ref.read(keyStoreProvider);
      final publicKey = await DevicePushKeys(keyStore).publicKeyBase64();

      await _ref.read(apiProvider).registerPush(
            platform: 'ios',
            pushToken: token,
            pushPublicKey: publicKey,
          );
      _startObservingLifecycle();
    } catch (_) {
      // Best-effort: an unreachable server, a permission denial that surfaced
      // as a platform error, or anything else here must not block sign-in or
      // crash the app.
    }
  }

  void _startObservingLifecycle() {
    if (_observingLifecycle) return;
    _observingLifecycle = true;
    WidgetsBinding.instance.addObserver(this);
    // Flutter does not replay the current state to a newly added observer, and
    // the server treats a foreground report as stale after a minute. Without
    // this first report a user who signs in and simply keeps reading is never
    // known to be foreground, so every message pushes a notification to the
    // screen they are already looking at.
    final current =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    unawaited(_reportLifecycle(_stateLabel(current)));
  }

  /// On iOS `inactive` is a visible-but-not-focused app: the Control Centre
  /// pulled down, the app switcher, an incoming call banner. Treating it as
  /// background would notify someone who is looking straight at the screen, so
  /// only a genuinely hidden app counts as background.
  static String _stateLabel(AppLifecycleState state) => switch (state) {
        AppLifecycleState.resumed || AppLifecycleState.inactive => 'foreground',
        _ => 'background',
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_reportLifecycle(_stateLabel(state)));
  }

  /// Drops this device's push registration and the key it was sealed to.
  /// Called on sign-out, while the owning session is still valid.
  Future<void> unregister() async {
    try {
      await _ref.read(apiProvider).unregisterPush();
    } catch (_) {
      // A server that cannot be reached still must not strand the user on the
      // settings screen; the registration is cleared server-side on session
      // revocation anyway.
    }
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
  }

  Future<void> _reportLifecycle(String state) async {
    try {
      await _ref.read(apiProvider).reportPushLifecycle(state: state);
    } catch (_) {
      // A dropped lifecycle ping just leaves the server's guess briefly
      // stale; never a reason to surface an error to the user.
    }
  }

  void dispose() {
    unawaited(_sessionSubscription.cancel());
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
