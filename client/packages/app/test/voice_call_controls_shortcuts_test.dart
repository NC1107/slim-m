// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A call had no keyboard shortcuts for mute, camera, share or leave, only
/// push-to-talk. Drives the real control row through the platform shortcut
/// table's default bindings rather than calling the controller directly, so
/// this is what a person actually pressing the keys would see happen.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_flags.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_call_controls_harness.dart';

Future<void> _pressPrimaryShift(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('Ctrl+Shift+M toggles the microphone', (tester) async {
    final container = await pumpControls(
      tester,
      const VoiceFlags(state: VoiceSessionState.connected),
    );
    final controller = container.read(voiceControllerProvider.notifier);
    expect(controller.state.microphoneEnabled, isTrue);

    await _pressPrimaryShift(tester, LogicalKeyboardKey.keyM);

    expect(
      controller.state.microphoneEnabled,
      isFalse,
      reason: 'the shortcut must reach the same toggle the mute button does',
    );
  });

  testWidgets('Ctrl+Shift+H leaves the call', (tester) async {
    final session = InertSession();
    await pumpControls(
      tester,
      const VoiceFlags(state: VoiceSessionState.connected),
      session: session,
    );

    await _pressPrimaryShift(tester, LogicalKeyboardKey.keyH);

    expect(
      session.leaveCalls,
      1,
      reason: 'the shortcut must reach the session the leave button does',
    );
  });
}
