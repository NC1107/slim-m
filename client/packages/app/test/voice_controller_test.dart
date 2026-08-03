// SPDX-License-Identifier: Apache-2.0
/// Tests for the one call this client can be in.
///
/// The controller's whole job is to keep what the UI shows honest about what
/// the SFU actually did, so these are mostly about the cases where the two
/// disagree: a token that cannot publish, a microphone the SFU refuses, a
/// deployment with no voice at all.
///
/// The iOS broadcast handoff has its own suite; both share a harness.
library;

import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

void main() {
  final harness = VoiceHarness();

  tearDown(harness.dispose);

  test('a listen-only token never asks for a microphone', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(canPublish: false),
    );

    await controller.join('channel-1');

    expect(controller.state.canPublish, isFalse);
    // Asking for a track the token forbids only produces a failure to report.
    expect(session.askedForMicrophoneOnJoin, isFalse);
  });

  test('a publishing token opens the microphone the user asked for', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');

    expect(controller.state.canPublish, isTrue);
    expect(session.askedForMicrophoneOnJoin, isTrue);
    expect(controller.state.error, isNull);
  });

  test('the camera stays off by default before joining', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    expect(controller.state.cameraEnabled, isFalse);
    await controller.join('channel-1');

    expect(session.askedForCameraOnJoin, isFalse);
  });

  test('a camera pre-toggle set before joining reaches the session', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    controller.setCameraPreference(true);
    await controller.join('channel-1');

    expect(controller.state.cameraEnabled, isTrue);
    expect(session.askedForCameraOnJoin, isTrue);
  });

  test('a listen-only token never asks for a camera either', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(canPublish: false),
    );

    controller.setCameraPreference(true);
    await controller.join('channel-1');

    // Same reasoning as the microphone: a forbidden track only reports.
    expect(session.askedForCameraOnJoin, isFalse);
  });

  test('a plain-ws SFU on a public address is refused, not joined', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(sfuUrl: 'ws://sfu.example.com'),
    );

    await controller.join('channel-1');

    expect(controller.state.state, VoiceSessionState.failed);
    expect(controller.state.error, contains('SLIMM_LIVEKIT_URL'));
    expect(
      controller.state.retryable,
      isFalse,
      reason: 'a misconfigured scheme fails identically on every retry',
    );
    expect(
      session.askedForMicrophoneOnJoin,
      isNull,
      reason: 'the session must never be asked to join an insecure SFU',
    );
  });

  test('a plain-ws SFU on a LAN address still joins', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(sfuUrl: 'ws://10.0.0.100:7880'),
    );

    await controller.join('channel-1');

    expect(controller.state.error, isNull);
    expect(session.askedForMicrophoneOnJoin, isTrue);
  });

  test('a wss SFU joins normally', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(sfuUrl: 'wss://sfu.example.com'),
    );

    await controller.join('channel-1');

    expect(controller.state.error, isNull);
    expect(session.askedForMicrophoneOnJoin, isTrue);
  });

  /// `SLIMM_LIVEKIT_URL` takes four schemes, not two - `voice/mod.rs`'s
  /// `http_url_for` accepts `wss`, `ws`, `https` and `http`, because LiveKit
  /// serves signalling on both pairs. Checking only for `wss` would refuse a
  /// perfectly secure deployment, which is a worse failure than the one this
  /// exists to prevent.
  test('an https SFU joins, and a plain-http public one is refused', () async {
    final secure = FakeSession();
    await harness
        .controllerWith(secure, voiceApi(sfuUrl: 'https://sfu.example.com'))
        .join('channel-1');
    expect(secure.askedForMicrophoneOnJoin, isTrue);

    final plain = FakeSession();
    final controller = harness.controllerWith(
      plain,
      voiceApi(sfuUrl: 'http://sfu.example.com'),
    );
    await controller.join('channel-1');
    expect(controller.state.state, VoiceSessionState.failed);
    expect(controller.state.retryable, isFalse);
    expect(plain.askedForMicrophoneOnJoin, isNull);
  });

  test(
    'a server with no voice says so, and is not a retryable failure',
    () async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi(status: 501));

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
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi(status: 403));

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

  /// The flagship regression this pass closes: `client_transport.dart` wraps
  /// any dropped connection in a string carrying the method, the path and the
  /// Dart exception, and that string used to reach this full-screen surface
  /// verbatim. A lost connection while joining a call is the reachable case
  /// (a mobile network transition), so this is the one the report named first.
  test(
    'a lost connection while joining renders a sentence, not the exception',
    () async {
      final session = FakeSession();
      final client = MockClient((request) async {
        throw const SocketException('connection refused');
      });
      final controller = harness.controllerWith(session, client);

      await controller.join('channel-1');

      expect(controller.state.state, VoiceSessionState.failed);
      expect(
        controller.state.error,
        isNot(contains('SocketException')),
        reason: 'a Dart exception string helps nobody and reads as a crash',
      );
      expect(controller.state.error, isNot(contains('/voice/token')));
      expect(
        controller.state.error,
        contains('the server could not be reached'),
      );
      expect(
        controller.state.retryable,
        isTrue,
        reason: 'a dropped connection might really succeed next time',
      );
    },
  );

  test(
    'a failed connection surfaces why, not just that, and stays retryable',
    () async {
      final session = FakeSession(joinOutcome: VoiceSessionState.failed);
      final controller = harness.controllerWith(session, voiceApi());

      await controller.join('channel-1');

      expect(controller.state.error, contains('the SFU refused'));
      expect(
        controller.state.retryable,
        isTrue,
        reason: 'a dropped connection might really succeed next time',
      );
    },
  );

  /// Uses the same controller throughout. An earlier version of this test
  /// built a second one, whose retryable defaults to true, so it passed even
  /// with the reset deleted.
  test('a retry after a non-retryable failure resets once it starts', () async {
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

    final controller = harness.controllerWith(FakeSession(), client);
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
    final session = FakeSession(microphoneGranted: false);
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    expect(controller.state.microphoneEnabled, isTrue);

    await controller.toggleMicrophone();

    // The SFU refused, so the button must not claim the microphone is muted.
    expect(controller.state.microphoneEnabled, isTrue);
    expect(controller.state.error, isNotNull);
  });

  test('a granted microphone toggle clears the previous error', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    await controller.setScreenShare(true);
    await controller.toggleMicrophone();

    expect(controller.state.microphoneEnabled, isFalse);
    expect(controller.state.error, isNull);
  });

  test('toggling the camera mid-call reaches the session', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    expect(controller.state.cameraEnabled, isFalse);

    await controller.toggleCamera();

    expect(controller.state.cameraEnabled, isTrue);
    expect(session.askedForCameraOnToggle, isTrue);
  });

  test('a refused camera toggle leaves the button where it was', () async {
    final session = FakeSession(cameraGranted: false);
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    await controller.toggleCamera();

    // The SFU refused, so the button must not claim the camera turned on.
    expect(controller.state.cameraEnabled, isFalse);
    expect(controller.state.error, isNotNull);
  });

  test(
    'a desktop that refuses the capture is reported, not shown as sharing',
    () async {
      final session = FakeSession(
        screenShareOutcome: ScreenShareOutcome.failed,
      );
      final controller = harness.controllerWith(session, voiceApi());

      await controller.join('channel-1');
      await controller.setScreenShare(true);

      expect(controller.state.screenSharing, isFalse);
      expect(controller.state.error, contains('Could not start sharing'));
    },
  );

  test('the session decides who is sharing, not the local toggle', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

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
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    expect(controller.state.deafened, isFalse);

    await controller.toggleDeafen();
    expect(controller.state.deafened, isTrue);

    await controller.toggleDeafen();
    expect(controller.state.deafened, isFalse);
  });

  test('a session that cannot deafen leaves the button where it was', () async {
    final session = FakeSession(deafenGranted: false);
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    await controller.toggleDeafen();

    expect(controller.state.deafened, isFalse);
    expect(controller.state.error, isNotNull);
  });

  test('leaving forgets the call entirely', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());

    await controller.join('channel-1');
    expect(controller.state.channelId, 'channel-1');

    await controller.leave();

    expect(session.leaveCalls, 1);
    expect(controller.state.channelId, isNull);
    expect(controller.state.state, VoiceSessionState.idle);
  });

  /// Since a voice channel now joins on arrival rather than behind a lobby
  /// with its own pre-toggles (see `voice_screen.dart`), the only place left
  /// to set "join muted" is whatever was last chosen mid-call - so leaving
  /// must not reset it back to the defaults.
  test(
    'leaving preserves the mic and camera preference for the next join',
    () async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());

      await controller.join('channel-1');
      await controller.toggleMicrophone();
      await controller.toggleCamera();
      expect(controller.state.microphoneEnabled, isFalse);
      expect(controller.state.cameraEnabled, isTrue);

      await controller.leave();

      expect(controller.state.microphoneEnabled, isFalse);
      expect(controller.state.cameraEnabled, isTrue);
    },
  );

  test('a drop the SFU decided on is reported, not silently idle', () async {
    final session = FakeSession();
    final controller = harness.controllerWith(session, voiceApi());
    await controller.join('channel-1');

    session.dropWith(VoiceDisconnect.replacedByOtherDevice);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.state, VoiceSessionState.failed);
    expect(
      controller.state.error,
      VoiceDisconnect.replacedByOtherDevice.message,
    );
  });

  test('a screen share failure carries the cause, not just a shrug', () async {
    final session = FakeSession(screenShareOutcome: ScreenShareOutcome.failed);
    final controller = harness.controllerWith(session, voiceApi());
    await controller.join('channel-1');

    await controller.setScreenShare(true);

    // Dropping this is what left the real Linux failure invisible.
    expect(controller.state.error, contains('source not found!'));
    expect(
      harness.log(controller).map((e) => e.message),
      contains(contains('Screen share start failed')),
    );
  });

  test('a chosen screen reaches the session', () async {
    final session = FakeSession(
      needsSource: true,
      sources: const [ScreenShareSource(id: 'screen-2', name: 'Screen 2')],
    );
    final controller = harness.controllerWith(session, voiceApi());
    await controller.join('channel-1');

    expect(controller.screenShareNeedsSource, isTrue);
    final sources = await controller.screenShareSources();
    await controller.setScreenShare(true, sourceId: sources.first.id);

    expect(session.lastSourceId, 'screen-2');
  });
}
