// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the suites that pump [CallControls]: its own
/// screen-share and camera behaviour, and its focus-ring reachability.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. See
/// `message_row_harness.dart` for the same split, done for the same reason.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/voice_call_controls.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

/// Mirrors `voice_settings_controller.dart`'s own private key: that file's
/// `VoiceSettingsController` is the real one under test here too, loaded from
/// `SharedPreferences` exactly as it is in the app, rather than swapped for a
/// fake - the bug this covers is that a saved value was never read back.
const qualityKey = 'slimm.voice.screen_share_quality';

/// The controls take their [VoiceState] as a parameter, so the session behind
/// the controller never has to reach any of these states itself.
class InertSession implements VoiceSession {
  InertSession({
    bool needsSource = false,
    Future<List<ScreenShareSource>>? sources,
    ScreenShareOutcome outcome = ScreenShareOutcome.started,
    bool sourcePickerUseful = true,
  }) : _needsSource = needsSource,
       _sources = sources ?? Future.value(const []),
       _outcome = outcome,
       screenShareSourcePickerUseful = sourcePickerUseful;

  final bool _needsSource;
  final Future<List<ScreenShareSource>> _sources;

  @override
  final bool screenShareSourcePickerUseful;

  /// Desktop starts sharing outright; `pendingBroadcast` is the iOS-only
  /// shape and is what would arm `VoiceController`'s 30-second broadcast
  /// deadline timer, which a test tapping share has to either not trigger or
  /// clean up before its own body ends.
  final ScreenShareOutcome _outcome;

  /// How many times a source list was actually requested, so a test can
  /// assert a fast double-tap only enumerated once.
  int sourceFetchCount = 0;

  /// Every call `setScreenShareEnabled` received, in order, so a test can
  /// assert on the quality it was actually given rather than only on the
  /// outcome.
  final List<({bool enabled, ScreenShareQuality quality, String? sourceId})>
  screenShareCalls = [];

  @override
  bool get supportsParticipantVolume => true;

  final Map<String, double> _volumes = {};

  @override
  double volumeFor(String identity) => _volumes[identity] ?? 1.0;

  @override
  Future<void> setVolumeFor(String identity, double volume) async {
    _volumes[identity] = volume.clamp(0.0, 2.0);
  }

  final _states = StreamController<VoiceSessionState>.broadcast();
  final _participants = StreamController<List<VoiceParticipant>>.broadcast();

  @override
  bool deafened = false;

  @override
  VoiceSessionState get state => VoiceSessionState.connected;

  @override
  Stream<VoiceSessionState> get states => _states.stream;

  @override
  List<VoiceParticipant> get participants => const [];

  @override
  Stream<List<VoiceParticipant>> get participantChanges => _participants.stream;

  @override
  Object? get lastError => null;

  @override
  VoiceDisconnect? get lastDisconnect => null;

  @override
  bool get screenShareNeedsSource => _needsSource;

  @override
  Future<List<ScreenShareSource>> screenShareSources() {
    sourceFetchCount += 1;
    return _sources;
  }

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

  @override
  Widget cameraViewFor(String identity) =>
      SizedBox.shrink(key: Key('fake-camera-view-$identity'));
  @override
  void setVideoInterest(Set<String>? tileKeys) {}

  @override
  void setSpeakingSensitivity(double sensitivity) {}

  /// Every camera-switching call this session received, in order, so a test
  /// can assert on how the control chose between flipping and picking.
  final List<String> cameraSwitchCalls = [];

  @override
  bool canFlipCamera = false;

  @override
  bool cameraNeedsSelection = false;

  List<CameraDevice> cameraDeviceList = const [];

  @override
  Future<List<CameraDevice>> cameraDevices() async => cameraDeviceList;

  @override
  Future<bool> flipCamera() async {
    cameraSwitchCalls.add('flip');
    return true;
  }

  @override
  Future<bool> selectCameraDevice(CameraDevice device) async {
    cameraSwitchCalls.add('select:${device.id}');
    return true;
  }

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

  /// Every call `setCameraEnabled` received, so a test can assert the
  /// toggle button actually reached the session.
  final List<bool> setCameraCalls = [];

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    setCameraCalls.add(enabled);
    return true;
  }

  @override
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    screenShareCalls.add((
      enabled: enabled,
      quality: quality,
      sourceId: sourceId,
    ));
    return _outcome;
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }
}

/// Pumps [CallControls] over a fresh, disposed-on-teardown provider
/// container, wired to [session] (a fresh [InertSession] if none is given).
Future<ProviderContainer> pumpControls(
  WidgetTester tester,
  VoiceState voice, {
  InertSession? session,
}) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      voiceControllerProvider.overrideWith(
        (ref) => VoiceController(ref, session: session ?? InertSession()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: CallControls(
            controller: container.read(voiceControllerProvider.notifier),
            voice: voice,
          ),
        ),
      ),
    ),
  );
  // pump, not pumpAndSettle: the pending state's progress spinner never settles.
  await tester.pump();
  return container;
}
