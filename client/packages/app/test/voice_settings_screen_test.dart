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
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_app/src/screens/settings_screen.dart';
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
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
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
  Future<bool> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
  }) async => enabled;

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
      home: child,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'out of a call, the meter says so instead of showing a live level',
    (tester) async {
      await tester.pumpWidget(_wrap(const VoiceSettingsScreen()));
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
    await tester.pumpWidget(_wrap(const VoiceSettingsScreen()));
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
        const VoiceSettingsScreen(),
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
      tester.element(find.byType(VoiceSettingsScreen)),
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
  });

  testWidgets('picking a screen share quality persists it', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Balanced'), findsOneWidget);
    await tester.tap(find.text('Crisp'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('slimm.voice.screen_share_quality'), 'crisp');
  });

  testWidgets('turning off join and leave sounds persists it', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is AppToggle && w.semanticLabel == 'Play join and leave sounds',
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('slimm.voice.join_leave_sounds_enabled'), isFalse);
  });

  testWidgets('the settings screen row reaches voice settings', (tester) async {
    final router = GoRouter(
      initialLocation: Routes.settings,
      routes: [
        GoRoute(
          path: Routes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: Routes.voiceSettings,
          builder: (context, state) => const VoiceSettingsScreen(),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
    );
    addTearDown(container.dispose);
    container.read(preferencesProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light, AppTokens.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The voice row sits past the list's cache extent now that appearance
    // and moderation sit above it, so it does not exist until scrolled to.
    await tester.scrollUntilVisible(
      find.text('Voice settings'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice settings'));
    await tester.pumpAndSettle();

    expect(find.byType(VoiceSettingsScreen), findsOneWidget);
  });
}
