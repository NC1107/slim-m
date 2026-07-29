// SPDX-License-Identifier: Apache-2.0
/// The join preview says who is already in the call.
///
/// The rail has shown this since the per-channel roster landed; the preview,
/// which is the screen you are actually on when deciding whether to join, did
/// not, and that was the last piece of the roadmap's voice-UX item.
///
/// The three answers the roster can give have to stay three different things.
/// A deployment with no SFU configured never leaves "not known", so rendering
/// that as an empty room would claim this client checked when it never did.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_design_system/design_system.dart';

const _channel = 'c-lounge';

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<List<api.VoiceRosterParticipant>> roster,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceRosterProvider(_channel).overrideWith(
          (ref) => switch (roster) {
            AsyncData(:final value) => Stream.value(value),
            _ => const Stream<List<api.VoiceRosterParticipant>>.empty(),
          },
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(body: VoiceScreen(channelId: _channel)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a roster that has not answered claims nothing', (tester) async {
    await _pump(tester, const AsyncLoading());

    expect(find.text('Join call'), findsOneWidget);
    expect(find.textContaining('Nobody is in this call'), findsNothing);
    expect(find.textContaining('here'), findsNothing);
  });

  testWidgets('a checked, empty room says so', (tester) async {
    await _pump(tester, const AsyncData([]));

    expect(find.text('Nobody is in this call yet.'), findsOneWidget);
  });

  testWidgets('the people already in it are named', (tester) async {
    await _pump(
      tester,
      const AsyncData([
        api.VoiceRosterParticipant(userId: 'u1', displayName: 'Ada'),
        api.VoiceRosterParticipant(userId: 'u2', displayName: 'Grace'),
      ]),
    );

    expect(find.textContaining('Ada'), findsWidgets);
    expect(find.textContaining('Grace'), findsWidgets);
    expect(find.text('Nobody is in this call yet.'), findsNothing);
  });

  testWidgets('one person reads as one person, not as a list', (tester) async {
    await _pump(
      tester,
      const AsyncData([
        api.VoiceRosterParticipant(userId: 'u1', displayName: 'Ada'),
      ]),
    );

    expect(find.text('Ada is here'), findsOneWidget);
  });
}
