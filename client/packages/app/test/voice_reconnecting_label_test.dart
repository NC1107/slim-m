// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The word that tells a rejoin apart from a first connection.
///
/// `voice_auto_rejoin_test.dart` asserts the provider reaches `rejoining`,
/// and nothing pumped a `VoiceScreen` to see what that renders. A grep for
/// "Reconnecting" across the app's tests matched only an unrelated error
/// string in a snapshot fixture, so the ternary at `voice_screen.dart:167`
/// had never been exercised either way.
///
/// It is one word, and it is the whole difference between "we lost you, hold
/// on" and "starting from scratch" for somebody watching a spinner.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/providers/voice_state.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Pumps the screen with the controller pinned to [voice] and returns the
/// container so the caller can tear it down.
Future<ProviderContainer> _pump(WidgetTester tester, VoiceState voice) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      voiceRosterProvider.overrideWith(
        (ref, channelId) => const Stream<List<VoiceRosterParticipant>>.empty(),
      ),
      voiceControllerProvider.overrideWith(
        (ref) => FixedVoiceController(ref, voice),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(body: VoiceScreen(channelId: 'c1')),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  // Fails: hardcoding `label: 'Connecting'`.
  testWidgets('a rejoin in this channel reads as Reconnecting', (tester) async {
    final container = await _pump(
      tester,
      const VoiceState(
        channelId: 'c1',
        state: VoiceSessionState.connecting,
        rejoining: true,
      ),
    );
    addTearDown(container.dispose);

    expect(find.text('Reconnecting'), findsOneWidget);
    expect(
      find.text('Connecting'),
      findsNothing,
      reason: 'the two words are the whole signal; showing both says neither',
    );
  });

  // Fails: hardcoding `label: 'Reconnecting'`.
  testWidgets('a first connection still reads as Connecting', (tester) async {
    final container = await _pump(
      tester,
      const VoiceState(channelId: 'c1', state: VoiceSessionState.connecting),
    );
    addTearDown(container.dispose);

    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Reconnecting'), findsNothing);
  });

  /// The case `rejoiningHere` is in the stage ternary *for*, and the one the
  /// three cases above miss.
  ///
  /// While an auto-rejoin waits between attempts the session has already
  /// failed, so `connectingHere` and `joiningHere` are both false. Without
  /// `rejoiningHere` the stage falls through to the rejoin screen and somebody
  /// whose network is coming back is told they left the call. Written after
  /// dropping that clause left the first three tests green.
  // Fails: dropping `|| rejoiningHere` from the stage ternary.
  testWidgets('a rejoin between attempts keeps the connecting stage', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const VoiceState(
        channelId: 'c1',
        state: VoiceSessionState.failed,
        rejoining: true,
      ),
    );
    addTearDown(container.dispose);

    expect(find.text('Reconnecting'), findsOneWidget);
    expect(
      find.text('You left this call.'),
      findsNothing,
      reason: 'a pending rejoin is not somebody having left',
    );
  });

  // Proves `rejoiningHere`'s channel gate is real, not incidental.
  testWidgets('a rejoin in another channel does not claim this one', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const VoiceState(
        channelId: 'other',
        state: VoiceSessionState.connecting,
        rejoining: true,
      ),
    );
    addTearDown(container.dispose);

    expect(find.text('Reconnecting'), findsNothing);
  });
}
