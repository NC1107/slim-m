// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for `voice_settings_screen_test.dart` and
/// `voice_settings_camera_test.dart`: a fake session, a voice token stub, and
/// the pane's own wrap.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it - split
/// out once the camera-on-join preference pushed the settings screen's own
/// suite over the 500-line hard ceiling, `voice_controller_harness.dart`'s
/// own precedent.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Answers the voice token endpoint the way `voice_controller_test.dart`'s
/// own helper does; nothing else here needs the network.
http.Client voiceTokenClient() => MockClient((request) async {
  if (!request.url.path.endsWith('/voice/token')) {
    return http.Response('{}', 404);
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

/// The minimum [VoiceSession] surface the controller needs, driven by hand.
/// Implemented rather than subclassed so a new member on the real session is
/// a compile error here, matching `voice_controller_test.dart`'s own fake.
class FakeSession implements VoiceSession {
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

  VoiceSessionState _state = VoiceSessionState.idle;

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
  Object? get lastError => null;

  @override
  VoiceDisconnect? get lastDisconnect => null;

  @override
  bool get screenShareNeedsSource => false;

  @override
  bool get screenShareSourcePickerUseful => true;

  @override
  Future<List<ScreenShareSource>> screenShareSources() async => const [];

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
  bool get canFlipCamera => false;

  @override
  bool get cameraNeedsSelection => false;

  @override
  Future<List<CameraDevice>> cameraDevices() async => const [];

  @override
  Future<bool> flipCamera() async => false;

  @override
  Future<bool> selectCameraDevice(CameraDevice device) async => false;

  /// What the controller actually passed through, so a test can assert the
  /// camera-on-join preference reached the join call rather than only the
  /// toggle's own visual state.
  bool? askedForCameraOnJoin;

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) async {
    askedForCameraOnJoin = cameraEnabled;
    _state = VoiceSessionState.connected;
    _states.add(_state);
  }

  @override
  Future<void> leave() async {
    _state = VoiceSessionState.idle;
    _states.add(_state);
  }

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => true;

  @override
  Future<bool> setCameraEnabled(bool enabled) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async => enabled ? ScreenShareOutcome.started : ScreenShareOutcome.stopped;

  @override
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }

  void emitParticipants(List<VoiceParticipant> p) => _participants.add(p);
}

Widget wrap(Widget child, {List<Override> overrides = const []}) {
  return UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        ...overrides,
      ],
    )..read(preferencesProvider),
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      // A pane body, not a screen: it needs the frame the settings scaffold gives it.
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}
