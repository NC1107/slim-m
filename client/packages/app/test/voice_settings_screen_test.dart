// SPDX-License-Identifier: Apache-2.0
/// Tests for the voice settings screen: the microphone meter reflects the
/// only real signal `slimm_rtc` exposes (a live call's local participant
/// speaking or not), and screen share quality and join/leave sounds are
/// preferences that survive a relaunch rather than a session-only echo.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/personal_settings_screen.dart';
import 'package:slimm_app/src/screens/voice_settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Answers the voice token endpoint the way `voice_controller_test.dart`'s
/// own helper does; nothing else here needs the network.
http.Client _voiceTokenClient() => MockClient((request) async {
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
class _FakeSession implements VoiceSession {
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
  }) async {
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

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        ...overrides,
      ],
    )..read(preferencesProvider),
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      // A pane body, not a screen: it gets its frame from the settings
      // scaffold in the app and needs an equivalent one here.
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'out of a call, the meter says so instead of showing a live level',
    (tester) async {
      await tester.pumpWidget(_wrap(const VoiceSettingsBody()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Join a voice call to see your live input level'),
        findsOneWidget,
      );
      final tween = tester
          .widget<TweenAnimationBuilder<double>>(
            find.byType(TweenAnimationBuilder<double>),
          )
          .tween;
      expect(tween.end, 6.0);
    },
  );

  testWidgets('device selection is reported as unavailable, not faked', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsBody()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Device selection is not available'),
      findsOneWidget,
    );
  });

  testWidgets('speaking in a live call raises the meter target', (
    tester,
  ) async {
    final session = _FakeSession();
    await tester.pumpWidget(
      _wrap(
        const VoiceSettingsBody(),
        overrides: [
          sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: _voiceTokenClient(),
            );
            ref.onDispose(api.close);
            return api;
          }),
          voiceControllerProvider.overrideWith(
            (ref) => VoiceController(ref, session: session),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final controller = ProviderScope.containerOf(
      tester.element(find.byType(VoiceSettingsBody)),
    ).read(voiceControllerProvider.notifier);
    await controller.join('channel-1');
    session.emitParticipants(const [
      VoiceParticipant(
        identity: 'me',
        name: 'me',
        isLocal: true,
        isSpeaking: true,
        isMuted: false,
        isScreenSharing: false,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Join a voice call to see your live input level'),
      findsNothing,
    );
    final tween = tester
        .widget<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>),
        )
        .tween;
    expect(tween.end, 82.0);
    // Clears the heartbeat timer a connected call now keeps running.
    await controller.leave();
  });

  testWidgets('picking a screen share quality persists it', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsBody()));
    await tester.pumpAndSettle();

    // The capability check section pushes this below the initial viewport.
    await tester.scrollUntilVisible(
      find.text('Crisp'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Balanced'), findsOneWidget);
    await tester.tap(find.text('Crisp'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('slimm.voice.screen_share_quality'), 'crisp');
  });

  testWidgets('turning off join and leave sounds persists it', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsBody()));
    await tester.pumpAndSettle();

    final soundsToggle = find.byWidgetPredicate(
      (w) => w is AppToggle && w.semanticLabel == 'Play join and leave sounds',
    );
    // The capability check section pushes this below the initial viewport.
    await tester.scrollUntilVisible(
      soundsToggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(soundsToggle);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('slimm.voice.join_leave_sounds_enabled'), isFalse);
  });

  testWidgets('turning off the incoming-call sound persists it', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsBody()));
    await tester.pumpAndSettle();

    final ringToggle = find.byWidgetPredicate(
      (w) =>
          w is AppToggle &&
          w.semanticLabel == 'Play a sound for an incoming call',
    );
    // The capability check section pushes this below the initial viewport.
    await tester.scrollUntilVisible(
      ringToggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(ringToggle);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('slimm.voice.call_ring_sound_enabled'), isFalse);
  });

  testWidgets('the Calls pane holds voice settings, with no second route', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
    );
    addTearDown(container.dispose);
    container.read(preferencesProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 900)),
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: const PersonalSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voice & screen share'));
    await tester.pumpAndSettle();

    expect(find.byType(VoiceSettingsBody), findsOneWidget);
    // The link row that used to push a second screen is gone with it.
    expect(find.text('Microphone, screen share, sounds'), findsNothing);
  });
}
