// SPDX-License-Identifier: Apache-2.0
/// Tests that the share control never claims a share that is not happening.
///
/// On iOS, asking to share only asks the system to offer a broadcast picker.
/// Capture runs in a separate ReplayKit extension process, and nothing is
/// published until the user starts the broadcast there. A control that lights
/// up on the request is describing something nobody can see, which is what the
/// owner reported as screen share doing nothing.
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

/// The controls take their [VoiceState] as a parameter, so the session behind
/// the controller never has to reach any of these states itself.
class _InertSession implements VoiceSession {
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
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
  }) async => ScreenShareOutcome.pendingBroadcast;

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }
}

void main() {
  Future<void> pumpControls(WidgetTester tester, VoiceState voice) async {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(ref, session: _InertSession()),
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
    // pump, not pumpAndSettle: the pending state runs a progress indicator,
    // which never settles.
    await tester.pump();
  }

  testWidgets('a share awaiting a broadcast reads as waiting, not as on', (
    tester,
  ) async {
    await pumpControls(
      tester,
      const VoiceState(
        state: VoiceSessionState.connected,
        awaitingBroadcast: true,
      ),
    );

    expect(find.byIcon(AppIcons.screenShare), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Waiting for you to start the broadcast. Tap to cancel.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a live share reads as sharing', (tester) async {
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected, screenSharing: true),
    );

    expect(find.byIcon(AppIcons.screenShare), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Stop sharing'), findsOneWidget);
  });
}
