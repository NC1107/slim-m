// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [NotificationSoundController]'s incoming-DM-call half: `call_ring` fires
/// only for a DM call actually starting live, never for the first catch-up
/// answer about one already under way, and never for a call this device is
/// already on.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/audio/notification_sound.dart';
import 'package:slimm_app/src/providers/dm_call_activity.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/notification_sound_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_settings_controller.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

class _FakeDmCallActivity extends DmCallActivityController {
  _FakeDmCallActivity(super.ref);

  void emit(Map<String, bool> next) => state = next;
}

/// A [VoiceController] whose channel can be set directly, with no SFU round
/// trip: this file only ever needs `channelId`, never a real call.
class _FixedChannelVoiceController extends VoiceController {
  _FixedChannelVoiceController(super.ref) : super(session: _DeadSession());

  void setChannel(String channelId) =>
      state = state.copyWith(channelId: channelId);
}

class _DeadSession implements VoiceSession {
  @override
  Stream<VoiceSessionState> get states => const Stream.empty();
  @override
  Stream<List<VoiceParticipant>> get participantChanges => const Stream.empty();
  @override
  List<VoiceParticipant> get participants => const [];
  @override
  VoiceSessionState get state => VoiceSessionState.idle;
  @override
  Object? get lastError => null;
  @override
  VoiceDisconnect? get lastDisconnect => null;
  @override
  bool deafened = false;
  @override
  bool get supportsParticipantVolume => false;
  @override
  bool get supportsScreenShareAudio => false;
  @override
  double volumeFor(String identity) => 1.0;
  @override
  Future<void> setVolumeFor(String identity, double volume) async {}
  @override
  bool get screenShareNeedsSource => false;
  @override
  bool get screenShareSourcePickerUseful => false;
  @override
  Future<List<ScreenShareSource>> screenShareSources() async => const [];
  @override
  bool isLocallyMuted(String identity) => false;
  @override
  Future<void> setLocallyMuted(String identity, bool muted) async {}
  @override
  Widget screenShareViewFor(String identity) => throw UnimplementedError();
  @override
  Widget cameraViewFor(String identity) => throw UnimplementedError();
  @override
  void setVideoInterest(Set<String>? tileKeys) {}
  @override
  void setSpeakingSensitivity(double sensitivity) {}
  @override
  bool get canFlipCamera => false;
  @override
  bool get cameraNeedsSelection => false;
  @override
  Future<List<CameraDevice>> cameraDevices() async => const [];
  @override
  Future<bool> flipCamera() async => false;
  @override
  Future<bool> selectCameraDevice(CameraDevice device) async => false;
  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) async {}
  @override
  Future<void> leave() async {}
  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => true;
  @override
  Future<bool> setCameraEnabled(bool enabled) async => true;
  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
    bool includeAudio = false,
    int? maxHeight,
  }) async => ScreenShareOutcome.stopped;
  @override
  Future<bool> setDeafened(bool value) async => true;
  @override
  Future<void> dispose() async {}
}

class _FakePlayer implements SoundPlayer {
  final played = <NotificationSound>[];

  @override
  Future<void> play(NotificationSound sound) async => played.add(sound);

  @override
  Future<void> dispose() async {}
}

const _tokens = api.TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

class _Setup {
  _Setup(this.container, this.activity, this.player);

  final ProviderContainer container;
  final _FakeDmCallActivity activity;
  final _FakePlayer player;
}

Future<_Setup> _wire() async {
  late _FakeDmCallActivity activity;
  final player = _FakePlayer();

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      liveEventsProvider.overrideWithValue(const Stream.empty()),
      dmCallActivityProvider.overrideWith((ref) {
        activity = _FakeDmCallActivity(ref);
        return activity;
      }),
      notificationSoundControllerProvider.overrideWith(
        (ref) => NotificationSoundController(ref, player: player),
      ),
    ],
  );
  container.read(notificationSoundControllerProvider);
  container.read(voiceSettingsControllerProvider);
  await pumpEventQueue();

  return _Setup(container, activity, player);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'the first, catch-up answer about an ongoing call plays nothing',
    () async {
      final setup = await _wire();
      setup.activity.emit({'dm-1': true});
      await pumpEventQueue();

      expect(setup.player.played, isEmpty);
    },
  );

  test('a DM call starting live after that plays call_ring', () async {
    final setup = await _wire();
    setup.activity.emit({'dm-1': false});
    await pumpEventQueue();
    setup.activity.emit({'dm-1': true});
    await pumpEventQueue();

    expect(setup.player.played, [NotificationSound.callRing]);
  });

  test('a DM call ending plays nothing', () async {
    final setup = await _wire();
    setup.activity.emit({'dm-1': true});
    await pumpEventQueue();
    setup.activity.emit({'dm-1': false});
    await pumpEventQueue();

    expect(setup.player.played, isEmpty);
  });

  test('a call this device already joined does not ring for itself', () async {
    late _FakeDmCallActivity activity;
    final player = _FakePlayer();
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        liveEventsProvider.overrideWithValue(const Stream.empty()),
        dmCallActivityProvider.overrideWith((ref) {
          activity = _FakeDmCallActivity(ref);
          return activity;
        }),
        voiceControllerProvider.overrideWith(_FixedChannelVoiceController.new),
        notificationSoundControllerProvider.overrideWith(
          (ref) => NotificationSoundController(ref, player: player),
        ),
      ],
    );
    container.read(notificationSoundControllerProvider);
    container.read(voiceSettingsControllerProvider);
    (container.read(voiceControllerProvider.notifier)
            as _FixedChannelVoiceController)
        .setChannel('dm-1');
    await pumpEventQueue();

    activity.emit({'dm-1': false});
    await pumpEventQueue();
    activity.emit({'dm-1': true});
    await pumpEventQueue();

    expect(player.played, isEmpty);
  });

  test('turning the incoming-call sound off silences a real ring', () async {
    final setup = await _wire();
    await setup.container
        .read(voiceSettingsControllerProvider.notifier)
        .setCallRingSoundEnabled(false);
    setup.activity.emit({'dm-1': false});
    await pumpEventQueue();
    setup.activity.emit({'dm-1': true});
    await pumpEventQueue();

    expect(setup.player.played, isEmpty);
  });
}
