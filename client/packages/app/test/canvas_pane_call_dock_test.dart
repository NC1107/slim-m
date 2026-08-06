// SPDX-License-Identifier: Apache-2.0
/// Wiring `CanvasPane` -> `CanvasCallDock`'s call section: it appears only
/// while this device is actually connected to a call in this exact channel,
/// the same "own channel, own connection" gate `CanvasPresenceLayer`'s own
/// wiring test already covers for camera bubbles.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/voice_call_controls.dart';
import 'package:slimm_rtc/rtc.dart';

import 'canvas_pane_harness.dart';
import 'voice_controller_harness.dart';

void main() {
  testWidgets(
    'connected to a call in this exact channel, the dock shows call controls',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(
                channelId: 'c1',
                state: VoiceSessionState.connected,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      expect(find.byType(CallControls), findsOneWidget);
    },
  );

  testWidgets(
    'connected to a call in a different channel, this canvas shows no call '
    'controls',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(
                channelId: 'a-different-channel',
                state: VoiceSessionState.connected,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      expect(find.byType(CallControls), findsNothing);
    },
  );

  testWidgets(
    'a join still in flight for this channel shows no call controls yet - '
    'only a connected call counts',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(
                channelId: 'c1',
                state: VoiceSessionState.connecting,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      expect(find.byType(CallControls), findsNothing);
    },
  );
}
