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

/// This device's push registration state, plain enough to read at a glance
/// off the settings screen rather than guessing from server logs, which is
/// exactly what a silent, un-diagnosable failure used to force.
enum PushStatus {
  /// Not signed in, so nothing has been attempted.
  notSignedIn,

  /// This platform has no push channel implemented yet (desktop, and for now
  /// Android too).
  unsupportedPlatform,

  /// Signed in and supported, but no device token has arrived yet: usually
  /// waiting on the permission prompt, or the wait timed out.
  noTokenYet,

  /// The native side reported the device token request itself failed.
  registrationFailed,

  /// A token was obtained, but telling the server about it failed.
  serverError,

  /// The server has this device's current token and push public key.
  registered,
}

/// A plain-English label for [PushStatus], for the settings screen.
extension PushStatusLabel on PushStatus {
  String get label => switch (this) {
        PushStatus.notSignedIn => 'Not signed in',
        PushStatus.unsupportedPlatform => 'Not available on this device',
        PushStatus.noTokenYet => 'Waiting on the notification permission',
        PushStatus.registrationFailed => 'The device could not register',
        PushStatus.serverError => 'Could not reach the server',
        PushStatus.registered => 'Registered for notifications',
      };
}

/// Registers this device's push token and encryption public key, and reports
/// foreground/background transitions once registered.
///
/// Session-driven, exactly like [SessionStore.changes] drives every other
/// controller in this app: a fresh sign-in and a session already restored at
/// launch both need the same retry, so neither is a special case here, only
/// the two moments the session can start being signed in. Only the
/// signed-out/signed-in edge triggers it, not every emission: the server
/// rotates access tokens well inside a live session, and re-running the whole
/// APNs fetch and registration on each routine rotation would be wasted work
/// at best, and at worst two overlapping first registrations racing to tell
/// the server which locally-generated keypair is current, leaving it holding
/// the public half of one the device already discarded. Every step past that
/// is best-effort: a user who denied notifications, or is running the Linux
/// desktop build where there is no APNs at all, must still get a fully
/// working app.
class PushController extends StateNotifier<PushStatus>
    with WidgetsBindingObserver {
  PushController(this._ref) : super(PushStatus.notSignedIn) {
    final session = _ref.read(sessionProvider);
    // Subscribe before reading the current value, so a change landing between
    // the two is never missed.
    _sessionSubscription = session.changes.listen((tokens) {
      final signedIn = tokens != null;
      if (signedIn == _lastSignedIn) return;
      _lastSignedIn = signedIn;
      if (signedIn) {
        unawaited(register());
      } else {
        state = PushStatus.notSignedIn;
      }
    });
    // Kept for this controller's whole life, not just while registered: a
    // failed attempt (denied permission, a slow token, a server that was down)
    // still needs to hear about the next resume to retry.
    WidgetsBinding.instance.addObserver(this);
    _lastSignedIn = session.isSignedIn;
    if (_lastSignedIn) unawaited(register());
  }

  final Ref _ref;
  late final StreamSubscription<TokenPair?> _sessionSubscription;
  bool _lastSignedIn = false;
  Future<void>? _registering;

  /// Fetches, or reuses, this device's push keypair and token, and tells the
  /// server about them. A no-op without a session, and every failure past
  /// that point is recorded in [state] rather than thrown, so a push problem
  /// never becomes an app problem.
  ///
  /// Non-reentrant: the session listener, a resume, and an explicit caller
  /// can all ask for this at once, and two concurrent attempts racing to
  /// register a keypair is exactly the failure this exists to close, so a
  /// call that arrives while one is already running shares it rather than
  /// starting a second.
  Future<void> register() {
    return _registering ??= _registerOnce().whenComplete(() {
      _registering = null;
    });
  }

  Future<void> _registerOnce() async {
    if (!_ref.read(sessionProvider).isSignedIn) {
      state = PushStatus.notSignedIn;
      return;
    }

    final result = await _ref.read(apnsTokenChannelProvider).fetch();
    switch (result) {
      case ApnsUnsupported():
        state = PushStatus.unsupportedPlatform;
      case ApnsTokenPending():
        state = PushStatus.noTokenYet;
      case ApnsRegistrationFailed():
        state = PushStatus.registrationFailed;
      case ApnsTokenReady(:final token):
        await _registerWithServer(token);
    }
  }

  Future<void> _registerWithServer(String token) async {
    try {
      final keyStore = _ref.read(keyStoreProvider);
      final publicKey = await DevicePushKeys(keyStore).publicKeyBase64();

      await _ref.read(apiProvider).registerPush(
            platform: 'ios',
            pushToken: token,
            pushPublicKey: publicKey,
          );
      state = PushStatus.registered;
      // Flutter does not replay the current lifecycle state to an observer
      // added earlier, and the server treats a foreground report as stale
      // after a minute. Without this the app can sit freshly registered but
      // never known to be foreground, so every message pushes a notification
      // to the screen the user is already looking at.
      final current =
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
      unawaited(_reportLifecycle(_stateLabel(current)));
    } catch (_) {
      state = PushStatus.serverError;
    }
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
    // A denied permission, a token that had not arrived yet, or a server that
    // was briefly unreachable all self-heal the same way: try again next time
    // the user opens the app, rather than staying silent until the next full
    // sign-in. `this.state` is the push status; the bare `state` parameter is
    // the lifecycle transition being reported.
    if (state == AppLifecycleState.resumed &&
        this.state != PushStatus.registered) {
      unawaited(register());
    }
    if (this.state == PushStatus.registered) {
      unawaited(_reportLifecycle(_stateLabel(state)));
    }
  }

  /// Drops this device's push registration and the key it was sealed to.
  /// Called on sign-out, while the owning session is still valid, and clears
  /// the local key too so the next account signed into this device gets a
  /// fresh one rather than inheriting this account's.
  Future<void> unregister() async {
    try {
      await _ref.read(apiProvider).unregisterPush();
    } catch (_) {
      // A server that cannot be reached still must not strand the user on the
      // settings screen; the registration is cleared server-side on session
      // revocation anyway.
    }
    try {
      await _ref.read(keyStoreProvider).delete(devicePushKeyHandle);
    } catch (_) {
      // Same reasoning as above: a key-store failure here must not abort
      // sign-out mid-way and leave sync already stopped but the session, and
      // the user, still stuck on the settings screen.
    }
    state = PushStatus.notSignedIn;
  }

  Future<void> _reportLifecycle(String lifecycleLabel) async {
    try {
      await _ref.read(apiProvider).reportPushLifecycle(state: lifecycleLabel);
    } catch (_) {
      // A dropped lifecycle ping just leaves the server's guess briefly
      // stale; never a reason to surface an error to the user.
    }
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final pushControllerProvider =
    StateNotifierProvider<PushController, PushStatus>(
        (ref) => PushController(ref));
