// SPDX-License-Identifier: Apache-2.0
/// [VoiceCallDock]: the canvas toggle it adds beside [CallControls], its own
/// DM self-gating, and the narrow-width fold that keeps a crowded row from
/// overflowing rather than shrinking any control below its 44dp floor.
///
/// `canvas_call_dock_touch_reach_test.dart` already proves the combined
/// call-and-canvas dock is reachable by a bare tap at 320; this file's job is
/// the dock this repo actually shows *before* the canvas ever opens, since
/// that is the one this task adds a control to.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane.dart';
import 'package:slimm_app/src/widgets/floating_dock_card.dart';
import 'package:slimm_rtc/rtc.dart' show VoiceSessionState;

import 'voice_call_controls_harness.dart';

const _connected = VoiceState(state: VoiceSessionState.connected);
const _connectedWithCamera = VoiceState(
  state: VoiceSessionState.connected,
  cameraEnabled: true,
);

void main() {
  testWidgets('the toggle opens the canvas, then closes it, at desktop width', (
    tester,
  ) async {
    final container = await pumpVoiceCallDock(
      tester,
      _connected,
      canvasChannelId: 'c1',
    );

    expect(container.read(canvasOpenProvider), isNull);

    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), 'c1');

    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), isNull);
  });

  testWidgets('the toggle reaches the same provider at phone width', (
    tester,
  ) async {
    final container = await pumpVoiceCallDock(
      tester,
      _connected,
      canvasChannelId: 'c1',
      width: 390,
      touch: true,
    );

    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), 'c1');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no toggle at all when canvas is not this call\'s to open - a DM call, '
    'CanvasCallDock passing null for its own reason',
    (tester) async {
      await pumpVoiceCallDock(tester, _connected, canvasChannelId: null);

      expect(find.bySemanticsLabel('Open canvas'), findsNothing);
      expect(
        tester.widget<FloatingDockCard>(find.byType(FloatingDockCard)).rows,
        hasLength(1),
      );
    },
  );

  testWidgets(
    'the row stays one line at the narrowest supported width when the '
    'camera is off, rather than folding when nothing forced it to',
    (tester) async {
      await pumpVoiceCallDock(
        tester,
        _connected,
        canvasChannelId: 'c1',
        width: 320,
        touch: true,
      );

      expect(
        tester.widget<FloatingDockCard>(find.byType(FloatingDockCard)).rows,
        hasLength(1),
        reason:
            'mic, camera, share, leave and the toggle all fit at 320 '
            'with the camera off; folding here would be needless crowding '
            'in the other direction',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the toggle folds into its own row, rather than overflowing the first '
    'one, once the camera is on at the narrowest supported width',
    (tester) async {
      await pumpVoiceCallDock(
        tester,
        _connectedWithCamera,
        canvasChannelId: 'c1',
        width: 320,
        touch: true,
      );

      expect(
        tester.widget<FloatingDockCard>(find.byType(FloatingDockCard)).rows,
        hasLength(2),
        reason:
            'mic, camera, switch camera, share, leave and the toggle no '
            'longer fit one line at 320, so the toggle must fold rather '
            'than overflow',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'a genuine RenderFlex overflow throws during the pump above',
      );

      // Every control, including the ones that stayed on the first row, is
      // still a bare tap away - folding the toggle must not have clipped or
      // stolen the hit area of anything beside it.
      await tester.tap(find.bySemanticsLabel('Mute'));
      await tester.tap(find.bySemanticsLabel('Switch camera'));
      await tester.tap(find.bySemanticsLabel('Open canvas'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the fold threshold is exact: one pixel narrower than what the camera-off '
    'row needs folds it, one pixel is not enough to avoid needing to',
    (tester) async {
      // 5 controls (mic, camera, share, leave, toggle), each 44dp plus the
      // 8dp AppFocusRing reserves on every edge (52dp total), 4 gaps of
      // 8dp, plus the card's own 12dp padding on both sides and its own
      // border's extra 1dp on each: 260+32+24+2.
      const exact = 318.0;
      await pumpVoiceCallDock(
        tester,
        _connected,
        canvasChannelId: 'c1',
        width: exact,
        touch: true,
      );
      expect(
        tester.widget<FloatingDockCard>(find.byType(FloatingDockCard)).rows,
        hasLength(1),
      );

      await pumpVoiceCallDock(
        tester,
        _connected,
        canvasChannelId: 'c1',
        width: exact - 1,
        touch: true,
      );
      expect(
        tester.widget<FloatingDockCard>(find.byType(FloatingDockCard)).rows,
        hasLength(2),
      );
    },
  );
}
