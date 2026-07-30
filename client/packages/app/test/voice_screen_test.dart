// SPDX-License-Identifier: Apache-2.0
/// Tests for the voice join preview's error handling: a failure this channel
/// cannot retry its way out of must not offer a button that only fails again,
/// and the one call controller's state must never leak across channels.
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
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
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

/// A [VoiceSession] this file never actually drives into a call: every test
/// here cares only about a failed `join`, before any session state matters.
class _NoopSession implements VoiceSession {
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

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
  }) async {}

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

http.Client _tokenApi(int status) => MockClient((request) async {
  if (status == 200) {
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
  }
  return http.Response(
    jsonEncode({
      'error': {'code': 'nope', 'message': 'refused'},
    }),
    status,
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
  testWidgets(
    'a server with no voice hides the join button rather than inviting a retry',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          // The preview polls this every 15 seconds now that it shows who
          // is already in the call; without a stub the timer outlives the test.
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
              httpClient: _tokenApi(501),
            );
            ref.onDispose(api.close);
            return api;
          }),
          voiceControllerProvider.overrideWith(
            (ref) => VoiceController(ref, session: _NoopSession()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), container),
      );
      await tester.pumpAndSettle();

      await container.read(voiceControllerProvider.notifier).join('channel-1');
      await tester.pumpAndSettle();

      expect(find.text('This Space has no voice configured.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join call'), findsNothing);
      // The shared component, not a hand-rolled Text: the surface the report named as reaching raw exceptions full-screen.
      expect(find.byType(AppErrorState), findsOneWidget);
    },
  );

  testWidgets(
    "a permission denial in one channel does not block joining another",
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          // The preview polls this every 15 seconds now that it shows who
          // is already in the call; without a stub the timer outlives the test.
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
              httpClient: _tokenApi(403),
            );
            ref.onDispose(api.close);
            return api;
          }),
          voiceControllerProvider.overrideWith(
            (ref) => VoiceController(ref, session: _NoopSession()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(voiceControllerProvider.notifier).join('channel-a');

      // Now looking at a different voice channel this account was never
      // refused: its join preview must start clean.
      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-b'), container),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to join this channel.'),
        findsNothing,
        reason: 'channel-a\'s denial must not leak into channel-b\'s preview',
      );
      expect(find.widgetWithText(FilledButton, 'Join call'), findsOneWidget);
    },
  );
}
