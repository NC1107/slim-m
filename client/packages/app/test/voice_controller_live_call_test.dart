// SPDX-License-Identifier: Apache-2.0
/// Tests for what happens once a call is live: toggling the microphone, the
/// camera, screen sharing, and deafening, plus leaving.
///
/// Split out of `voice_controller_test.dart`, which sat at this repo's
/// 500-line hard ceiling before the camera-refusal diagnostics grew it past
/// it; joining a call (the token round trip, the insecure-scheme refusal)
/// stays there. Both share a harness.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

void main() {
  final harness = VoiceHarness();

  tearDown(harness.dispose);

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
    'a refused camera toggle surfaces why, not just that, and logs it',
    () async {
      final session = FakeSession(cameraGranted: false);
      final controller = harness.controllerWith(session, voiceApi());

      await controller.join('channel-1');
      await controller.toggleCamera();

      expect(controller.state.error, contains('no camera device found'));
      expect(
        harness
            .log(controller)
            .any((e) => e.detail == 'no camera device found'),
        isTrue,
        reason: 'the cause must reach the debug log, not only the screen',
      );
    },
  );

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
