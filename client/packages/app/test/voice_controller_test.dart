// SPDX-License-Identifier: Apache-2.0
/// Tests for the one call this client can be in.
///
/// The controller's whole job is to keep what the UI shows honest about what
/// the SFU actually did, so these are mostly about the cases where the two
/// disagree: a token that cannot publish, a microphone the SFU refuses, a
/// deployment with no voice at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A [VoiceSession] the test drives by hand.
///
/// Implemented rather than subclassed so that adding a method to the real
/// session is a compile error here, not a silently untested path.
class _FakeSession implements VoiceSession {
  _FakeSession({
    this.joinOutcome = VoiceSessionState.connected,
    this.microphoneGranted = true,
    this.screenShareGranted = true,
    this.deafenGranted = true,
  });

  final VoiceSessionState joinOutcome;
  final bool microphoneGranted;
  final bool screenShareGranted;
  final bool deafenGranted;

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

  @override
  Object? get lastError =>
      _state == VoiceSessionState.failed ? 'the SFU refused' : null;

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
  Future<bool> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
  }) async => enabled ? screenShareGranted : false;

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
http.Client _api({int status = 200, bool canPublish = true}) {
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

void main() {
  late ProviderContainer container;

  tearDown(() => container.dispose());

  /// The controller as the app builds it, with only the network and the SFU
  /// swapped: a real session, a real [SlimmApi], and the same provider wiring.
  VoiceController controllerWith(_FakeSession session, http.Client client) {
    container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
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
          (ref) => VoiceController(ref, session: session),
        ),
      ],
    );
    return container.read(voiceControllerProvider.notifier);
  }

  test('a listen-only token never asks for a microphone', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api(canPublish: false));

    await controller.join('channel-1');

    expect(controller.state.canPublish, isFalse);
    // Asking for a track the token forbids only produces a failure to report.
    expect(session.askedForMicrophoneOnJoin, isFalse);
  });

  test('a publishing token opens the microphone the user asked for', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');

    expect(controller.state.canPublish, isTrue);
    expect(session.askedForMicrophoneOnJoin, isTrue);
    expect(controller.state.error, isNull);
  });

  test(
    'a server with no voice says so, and is not a retryable failure',
    () async {
      final session = _FakeSession();
      final controller = controllerWith(session, _api(status: 501));

      await controller.join('channel-1');

      expect(controller.state.state, VoiceSessionState.failed);
      expect(controller.state.error, contains('no voice configured'));
      expect(
        controller.state.retryable,
        isFalse,
        reason: 'the server config will not change from clicking Join again',
      );
    },
  );

  test(
    'being refused the channel reads as permission, not as a fault',
    () async {
      final session = _FakeSession();
      final controller = controllerWith(session, _api(status: 403));

      await controller.join('channel-1');

      expect(controller.state.state, VoiceSessionState.failed);
      expect(controller.state.error, contains('permission'));
      expect(
        controller.state.retryable,
        isFalse,
        reason: 'a permission denial will not change from clicking Join again',
      );
    },
  );

  test(
    'a failed connection surfaces why, not just that, and stays retryable',
    () async {
      final session = _FakeSession(joinOutcome: VoiceSessionState.failed);
      final controller = controllerWith(session, _api());

      await controller.join('channel-1');

      expect(controller.state.error, contains('the SFU refused'));
      expect(
        controller.state.retryable,
        isTrue,
        reason: 'a dropped connection might really succeed next time',
      );
    },
  );

  test('a retry after a non-retryable failure resets once it starts', () async {
    // The same controller throughout. An earlier version of this test built a
    // second one, whose retryable defaults to true, so it passed even with the
    // reset deleted.
    var status = 501;
    final client = MockClient((request) async {
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
          'can_publish': true,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final controller = controllerWith(_FakeSession(), client);
    await controller.join('channel-1');
    expect(
      controller.state.retryable,
      isFalse,
      reason: 'a server with no voice is not worth retrying',
    );

    // The admin configures an SFU and the user tries again.
    status = 200;
    await controller.join('channel-1');

    expect(
      controller.state.retryable,
      isTrue,
      reason: 'the previous failure must not lock this controller out',
    );
    expect(controller.state.error, isNull);
  });

  test('a refused microphone leaves the button where it was', () async {
    final session = _FakeSession(microphoneGranted: false);
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    expect(controller.state.microphoneEnabled, isTrue);

    await controller.toggleMicrophone();

    // The SFU refused, so the button must not claim the microphone is muted.
    expect(controller.state.microphoneEnabled, isTrue);
    expect(controller.state.error, isNotNull);
  });

  test('a granted microphone toggle clears the previous error', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    await controller.setScreenShare(true);
    await controller.toggleMicrophone();

    expect(controller.state.microphoneEnabled, isFalse);
    expect(controller.state.error, isNull);
  });

  test(
    'a desktop that refuses the capture is reported, not shown as sharing',
    () async {
      final session = _FakeSession(screenShareGranted: false);
      final controller = controllerWith(session, _api());

      await controller.join('channel-1');
      await controller.setScreenShare(true);

      expect(controller.state.screenSharing, isFalse);
      expect(controller.state.error, contains('refused the capture'));
    },
  );

  test('the session decides who is sharing, not the local toggle', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    await controller.setScreenShare(true);
    expect(controller.state.screenSharing, isTrue);

    // The SFU drops the track without the local toggle changing.
    session.emitParticipants(const [
      VoiceParticipant(
        identity: 'user-1',
        name: 'me',
        isLocal: true,
        isSpeaking: false,
        isMuted: false,
        isScreenSharing: false,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.screenSharing, isFalse);
  });

  test('deafening reflects what the session actually did', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    expect(controller.state.deafened, isFalse);

    await controller.toggleDeafen();
    expect(controller.state.deafened, isTrue);

    await controller.toggleDeafen();
    expect(controller.state.deafened, isFalse);
  });

  test('a session that cannot deafen leaves the button where it was', () async {
    final session = _FakeSession(deafenGranted: false);
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    await controller.toggleDeafen();

    expect(controller.state.deafened, isFalse);
    expect(controller.state.error, isNotNull);
  });

  test('leaving forgets the call entirely', () async {
    final session = _FakeSession();
    final controller = controllerWith(session, _api());

    await controller.join('channel-1');
    expect(controller.state.channelId, 'channel-1');

    await controller.leave();

    expect(session.leaveCalls, 1);
    expect(controller.state.channelId, isNull);
    expect(controller.state.state, VoiceSessionState.idle);
  });
}
