// SPDX-License-Identifier: Apache-2.0
/// The camera pre-toggle on the voice join preview: absent, not disabled,
/// used to be the honest state - now the toggle is real, and this pins that
/// tapping it flips the preference the same way the microphone one already
/// does, and that the preference actually reaches the session on join.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Records what it was asked for on join, never actually connecting: these
/// tests only care about the preference reaching the session.
class _RecordingSession implements VoiceSession {
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
  VoiceSessionState get state => VoiceSessionState.idle;

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

  bool? askedForCameraOnJoin;

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) async {
    askedForCameraOnJoin = cameraEnabled;
  }

  @override
  Future<void> leave() async {}

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async => ScreenShareOutcome.started;

  @override
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }
}

http.Client _tokenApi() => MockClient((request) async {
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

Widget _harness(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('the camera pre-toggle starts off and reads as off', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: _tokenApi(),
          );
          ref.onDispose(api.close);
          return api;
        }),
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(ref, session: _RecordingSession()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _harness(const VoiceScreen(channelId: 'channel-1'), container),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
  });

  testWidgets(
    'tapping the camera pre-toggle flips it, and the preference reaches the session on join',
    (tester) async {
      final session = _RecordingSession();
      final container = ProviderContainer(
        overrides: [
          voiceRosterProvider.overrideWith(
            (ref, channelId) =>
                const Stream<List<VoiceRosterParticipant>>.empty(),
          ),
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: _tokenApi(),
            );
            ref.onDispose(api.close);
            return api;
          }),
          voiceControllerProvider.overrideWith(
            (ref) => VoiceController(ref, session: session),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), container),
      );
      await tester.pumpAndSettle();

      // "on" already appears once, for the microphone's own default value.
      await tester.tap(find.text('Camera'));
      await tester.pump();
      expect(find.text('on'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilledButton, 'Join call'));
      await tester.pumpAndSettle();

      expect(session.askedForCameraOnJoin, isTrue);
    },
  );
}
