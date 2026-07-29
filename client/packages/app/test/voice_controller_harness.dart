// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the two suites that drive a [VoiceController]: the
/// controller's own behaviour, and the iOS broadcast handoff.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. Both
/// suites need the same hand-driven [VoiceSession], the same token endpoint
/// and the same provider wiring around them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/diagnostics/debug_log.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A [VoiceSession] the test drives by hand.
///
/// Implemented rather than subclassed so that adding a method to the real
/// session is a compile error here, not a silently untested path.
class FakeSession implements VoiceSession {
  FakeSession({
    this.joinOutcome = VoiceSessionState.connected,
    this.microphoneGranted = true,
    this.screenShareOutcome = ScreenShareOutcome.started,
    this.deafenGranted = true,
    this.needsSource = false,
    this.sources = const [],
  });

  final VoiceSessionState joinOutcome;
  final bool microphoneGranted;

  /// What a request to start sharing reports back. Every branch the
  /// controller has to tell apart is one of these.
  final ScreenShareOutcome screenShareOutcome;
  final bool deafenGranted;

  /// Whether this platform makes a share name a screen first.
  final bool needsSource;
  final List<ScreenShareSource> sources;

  /// What the controller actually passed through, so a test can assert the
  /// chosen screen reached the session rather than being dropped.
  String? lastSourceId;
  int sourceListings = 0;

  final _states = StreamController<VoiceSessionState>.broadcast();
  final _participants = StreamController<List<VoiceParticipant>>.broadcast();

  VoiceSessionState _state = VoiceSessionState.idle;
  bool? askedForMicrophoneOnJoin;
  int leaveCalls = 0;

  @override
  bool deafened = false;

  @override
  VoiceSessionState get state => _state;

  @override
  Stream<VoiceSessionState> get states => _states.stream;

  @override
  List<VoiceParticipant> get participants => const [];

  @override
  Stream<List<VoiceParticipant>> get participantChanges => _participants.stream;

  Object? _lastError;

  @override
  Object? get lastError =>
      _lastError ??
      (_state == VoiceSessionState.failed ? 'the SFU refused' : null);

  @override
  VoiceDisconnect? lastDisconnect;

  @override
  bool get screenShareNeedsSource => needsSource;

  @override
  Future<List<ScreenShareSource>> screenShareSources() async {
    sourceListings++;
    return sources;
  }

  /// Keyed so a widget test can assert the share surface mounted for the
  /// right participant without a real room behind it.
  final Set<String> _locallyMuted = {};

  @override
  bool isLocallyMuted(String identity) => _locallyMuted.contains(identity);

  @override
  Future<void> setLocallyMuted(String identity, bool muted) async {
    muted ? _locallyMuted.add(identity) : _locallyMuted.remove(identity);
  }

  @override
  Widget screenShareViewFor(String identity) =>
      SizedBox.shrink(key: Key('fake-share-view-$identity'));

  /// Drives a drop the SFU decided on, the way a real room event would.
  void dropWith(VoiceDisconnect reason) {
    lastDisconnect = reason;
    _state = VoiceSessionState.failed;
    _states.add(_state);
  }

  /// Pushes any other session-state transition through the same stream
  /// `join`'s own outcome never emits on, since nothing here drives a real
  /// `Room`'s events.
  void emitState(VoiceSessionState next) {
    _state = next;
    _states.add(next);
  }

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
  }) async {
    askedForMicrophoneOnJoin = microphoneEnabled;
    _state = joinOutcome;
  }

  @override
  Future<void> leave() async {
    leaveCalls++;
    _state = VoiceSessionState.idle;
  }

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => microphoneGranted;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    lastSourceId = sourceId;
    if (!enabled) return ScreenShareOutcome.stopped;
    // The real session records why before reporting failure; a fake that does
    // not cannot catch a controller that drops the cause.
    if (screenShareOutcome == ScreenShareOutcome.failed) {
      _lastError = 'source not found!';
    }
    return screenShareOutcome;
  }

  @override
  Future<bool> setDeafened(bool value) async {
    if (!deafenGranted) return false;
    deafened = value;
    return true;
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }

  void emitParticipants(List<VoiceParticipant> p) => _participants.add(p);
}

/// Answers the token endpoint however the test asks, and nothing else.
http.Client voiceApi({int status = 200, bool canPublish = true}) {
  return MockClient((request) async {
    if (!request.url.path.endsWith('/voice/token')) {
      return http.Response('{}', 404);
    }
    if (status != 200) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'nope', 'message': 'refused'},
        }),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'url': 'wss://sfu.example.com',
        'room': 'channel-1',
        'token': 'jwt',
        'expires_at': 0,
        'can_publish': canPublish,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

/// Owns the container so a suite can tear it down in one place.
class VoiceHarness {
  ProviderContainer? _container;

  /// For a widget test to wrap in `UncontrolledProviderScope`; only valid
  /// after [controllerWith] has built one.
  ProviderContainer get container => _container!;

  void dispose() => _container?.dispose();

  /// What the controller recorded for the user to read back in settings.
  List<DiagnosticEvent> log(VoiceController _) =>
      _container!.read(debugLogProvider);

  /// The controller as the app builds it, with only the network and the SFU
  /// swapped: a real session, a real [SlimmApi], and the same provider wiring.
  VoiceController controllerWith(
    FakeSession session,
    http.Client client, {
    Duration broadcastStartTimeout = const Duration(seconds: 30),
  }) {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: tokens)),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: client,
          );
          ref.onDispose(api.close);
          return api;
        }),
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(
            ref,
            session: session,
            broadcastStartTimeout: broadcastStartTimeout,
          ),
        ),
      ],
    );
    _container = container;
    return container.read(voiceControllerProvider.notifier);
  }
}
