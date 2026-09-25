// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The alone-in-a-call hint: a solo caller with nobody sharing gets a calm
/// waiting message and a canvas hint, neither of which the with-others
/// state shows. See `call_stage_layout.dart`'s `_AloneHint`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

const _me = VoiceParticipant(
  identity: 'user-1',
  name: 'Me',
  isLocal: true,
  isSpeaking: false,
  isMuted: false,
  isScreenSharing: false,
);

const _alice = VoiceParticipant(
  identity: 'user-2',
  name: 'Alice',
  isLocal: false,
  isSpeaking: false,
  isMuted: false,
  isScreenSharing: false,
);

Widget _harness(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: child),
      ),
    );

const _hintText = 'Waiting for others to join.';
const _canvasHintText = 'Open the canvas below while you wait';

void main() {
  testWidgets('a solo caller sees the waiting hint and a canvas hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = VoiceHarness();
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(),
      extraOverrides: [
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
      ],
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
    );
    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await tester.pump();
    session.emitParticipants(const [_me]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsOneWidget);
    expect(
      find.text(_canvasHintText),
      findsOneWidget,
      reason: 'a real voice channel gets the canvas hint',
    );

    session.emitParticipants(const [_me, _alice]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text(_hintText),
      findsNothing,
      reason: 'the hint disappears the moment a second participant joins',
    );
    expect(find.text(_canvasHintText), findsNothing);

    await harness.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('with others present, no hint and the ordinary header copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = VoiceHarness();
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(),
      extraOverrides: [
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
      ],
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
    );
    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await tester.pump();
    session.emitParticipants(const [_me, _alice]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsNothing);
    expect(find.text('2 in call'), findsOneWidget);

    await harness.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('a DM call gets the waiting text but no canvas hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = VoiceHarness();
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(),
      extraOverrides: [
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
      ],
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _harness(
        const VoiceScreen(channelId: 'channel-1', isDm: true),
        harness.container,
      ),
    );
    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await tester.pump();
    session.emitParticipants(const [_me]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsOneWidget);
    expect(find.text(_canvasHintText), findsNothing);

    await harness.container.read(voiceControllerProvider.notifier).leave();
  });
}
