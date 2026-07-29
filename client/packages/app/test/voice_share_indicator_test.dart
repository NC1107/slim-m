// SPDX-License-Identifier: Apache-2.0
/// Tests for the local screen-share indicator: the in-call banner and the
/// collapsed strip both have to show a live share, and both have to stay
/// quiet for a share that is only requested, never actually live.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_app/src/widgets/voice_strip_indicator.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

Widget _harness(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  final harness = VoiceHarness();
  tearDown(harness.dispose);

  group('the in-call banner', () {
    testWidgets('shows for a live share', (tester) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
      );
      await tester.pump();
      await controller.setScreenShare(true);
      await tester.pump();

      expect(find.text('You are sharing your screen.'), findsOneWidget);
    });

    testWidgets('stays quiet for a share only requested, not live', (
      tester,
    ) async {
      final session = FakeSession(
        screenShareOutcome: ScreenShareOutcome.pendingBroadcast,
      );
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
      );
      await tester.pump();
      await controller.setScreenShare(true);
      await tester.pump();

      expect(controller.state.awaitingBroadcast, isTrue);
      expect(find.text('You are sharing your screen.'), findsNothing);

      // Clears the pending-broadcast deadline timer before the test ends.
      await controller.setScreenShare(false);
    });

    testWidgets('stays quiet with no share at all', (tester) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
      );
      await tester.pump();

      expect(find.text('You are sharing your screen.'), findsNothing);
    });
  });

  group('the share stage', () {
    testWidgets('renders a remote share, named for its sharer', (tester) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
      );
      await tester.pump();
      session.emitParticipants(const [
        VoiceParticipant(
          identity: 'me',
          name: 'Me',
          isSpeaking: false,
          isMuted: false,
          isLocal: true,
          isScreenSharing: false,
        ),
        VoiceParticipant(
          identity: 'peer-1',
          name: 'Ada',
          isSpeaking: false,
          isMuted: false,
          isLocal: false,
          isScreenSharing: true,
        ),
      ]);
      await tester.pump();

      // The stage mounted, wired to the sharing participant specifically.
      expect(find.byKey(const Key('fake-share-view-peer-1')), findsOneWidget);
      expect(find.text("Ada's screen"), findsOneWidget);
    });

    testWidgets('your own share gets the banner, never an echo stage', (
      tester,
    ) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceScreen(channelId: 'channel-1'), harness.container),
      );
      await tester.pump();
      session.emitParticipants(const [
        VoiceParticipant(
          identity: 'me',
          name: 'Me',
          isSpeaking: false,
          isMuted: false,
          isLocal: true,
          isScreenSharing: true,
        ),
      ]);
      await tester.pump();

      expect(find.text('You are sharing your screen.'), findsOneWidget);
      expect(find.byKey(const Key('fake-share-view-me')), findsNothing);
    });
  });

  group('the collapsed strip', () {
    testWidgets('names the share in words for a live share', (tester) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceStripIndicator(), harness.container),
      );
      await tester.pump();
      await controller.setScreenShare(true);
      await tester.pump();

      // Said in words, not left to a small glyph a tooltip has to explain: the
      // collapsed strip is exactly where a live share is easiest to miss.
      expect(find.textContaining('Sharing your screen'), findsOneWidget);
    });

    testWidgets('stays quiet for a share only requested, not live', (
      tester,
    ) async {
      final session = FakeSession(
        screenShareOutcome: ScreenShareOutcome.pendingBroadcast,
      );
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceStripIndicator(), harness.container),
      );
      await tester.pump();
      await controller.setScreenShare(true);
      await tester.pump();

      expect(controller.state.awaitingBroadcast, isTrue);
      expect(find.textContaining('Sharing your screen'), findsNothing);

      // Clears the pending-broadcast deadline timer before the test ends.
      await controller.setScreenShare(false);
    });

    testWidgets('stays quiet with no share at all', (tester) async {
      final session = FakeSession();
      final controller = harness.controllerWith(session, voiceApi());
      await controller.join('channel-1');
      session.emitState(VoiceSessionState.connected);

      await tester.pumpWidget(
        _harness(const VoiceStripIndicator(), harness.container),
      );
      await tester.pump();

      expect(find.textContaining('Sharing your screen'), findsNothing);
    });
  });
}
