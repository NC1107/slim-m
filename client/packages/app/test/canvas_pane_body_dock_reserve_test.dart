// SPDX-License-Identifier: Apache-2.0
/// `CanvasPaneBody._dockBottomReserve`: the self bubble's reserved space
/// must agree with `CanvasCallDock`'s own one-row/two-row branch, or the
/// bubble rests where the dock actually paints over it.
///
/// Found by rendering the assembled pane at real widths rather than by
/// reading the code: `_dockBottomReserve` compared the raw pane width
/// against `kCompactWidth`, but `CanvasCallDock`'s own `LayoutBuilder` sees
/// that width minus the `Padding(EdgeInsets.all(AppSpacing.s12))` it is
/// wrapped in - a 24dp gap the reserve calculation never subtracted. For
/// any pane width in `[kCompactWidth, kCompactWidth + 24)` the dock still
/// drew two rows while the reserve assumed one, so the self bubble's
/// resting position sat inside the dock's own second row instead of above
/// it, and the dock - painted after it in `CanvasPaneBody`'s outer `Stack`
/// - covered the bottom of the bubble.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/canvas_self_presence.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_activity_log.dart';
import 'package:slimm_app/src/screens/canvas/canvas_call_dock.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane_body.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_app/src/screens/canvas/canvas_self_presence_overlay.dart';
import 'package:slimm_app/src/widgets/floating_dock_card.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'voice_controller_harness.dart';

const _participants = [
  VoiceParticipant(
    identity: 'me',
    name: 'Me',
    isSpeaking: false,
    isMuted: false,
    isLocal: true,
    isScreenSharing: false,
  ),
  VoiceParticipant(
    identity: 'other',
    name: 'Other',
    isSpeaking: false,
    isMuted: false,
    isLocal: false,
    isScreenSharing: false,
  ),
];

/// Mounts a real [CanvasPaneBody] with a connected call at [width]x900, the
/// only shape that reaches both `FloatingDockCard` and `CanvasPresenceBubble`
/// at once.
Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      voiceControllerProvider.overrideWith(
        (ref) => FixedVoiceController(
          ref,
          const VoiceState(
            channelId: 'c1',
            state: VoiceSessionState.connected,
            participants: _participants,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final controller = container.read(voiceControllerProvider.notifier);
  final document = CanvasDocument();
  addTearDown(document.dispose);
  final activityLog = CanvasActivityLog(isBlocked: (_) => false);
  addTearDown(activityLog.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: CanvasPaneBody(
            channelId: 'c1',
            onClose: () {},
            tool: CanvasTool.pen,
            onToolChanged: (_) {},
            canUndo: false,
            onUndo: () {},
            canManage: false,
            document: document,
            onClear: () async {},
            onPasteImage: () {},
            onRecenter: () {},
            error: null,
            onDismissError: () {},
            truncated: false,
            loading: false,
            onStroke: (_) {},
            onErase: (_) {},
            onEraseEnd: () {},
            onSelectStart: (_) {},
            onSelectDrag: (_) {},
            onSelectEnd: () {},
            onNotePlace: (_) {},
            onShapePlace: (_) {},
            shapeKind: CanvasShapeKind.rectangle,
            onShapeKindChanged: (_) {},
            onBringToFront: (_) {},
            onSendToBack: (_) {},
            onDeleteSelected: (_) {},
            selfId: 'me',
            activityLog: activityLog,
            callParticipants: _participants,
            cameraViewFor: (_) => const SizedBox(),
            selfBubbleHidden: false,
            selfBubbleCorner: CanvasSelfBubbleCorner.bottomRight,
            onSelfBubbleCornerChanged: (_) {},
            onToggleSelfBubbleHidden: () {},
            callDock: CallDockData(
              voice: const VoiceState(
                channelId: 'c1',
                state: VoiceSessionState.connected,
                participants: _participants,
              ),
              controller: controller,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// The self bubble specifically, scoped past `CanvasSelfPresenceOverlay` -
/// a remote participant's own `CanvasPresenceBubble` shares the same widget
/// type, so an unscoped `find.byType` is ambiguous whenever the roster
/// carries anyone else too.
final _selfBubble = find.descendant(
  of: find.byType(CanvasSelfPresenceOverlay),
  matching: find.byType(CanvasPresenceBubble),
);

void main() {
  for (final width in [600.0, 610.0, 623.0]) {
    testWidgets('at pane width $width, inside the dock\'s own padding-shifted '
        'two-row band, the self bubble still rests above the dock', (
      tester,
    ) async {
      await _pump(tester, width);

      final bubble = tester.getRect(_selfBubble);
      final dock = tester.getRect(find.byType(FloatingDockCard));
      expect(
        bubble.bottom,
        lessThanOrEqualTo(dock.top),
        reason:
            'the dock paints after the bubble in the outer Stack, so any '
            'overlap here means the dock visually covers the bubble',
      );
    });
  }

  testWidgets(
    'at pane width 900, safely past the padding-shifted band, the bubble '
    'still rests above the one-row dock',
    (tester) async {
      await _pump(tester, 900);

      final bubble = tester.getRect(_selfBubble);
      final dock = tester.getRect(find.byType(FloatingDockCard));
      expect(bubble.bottom, lessThanOrEqualTo(dock.top));
    },
  );
}
