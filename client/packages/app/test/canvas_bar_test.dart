// SPDX-License-Identifier: Apache-2.0
/// The canvas bar in isolation: the pen/eraser toggle, the undo button's
/// enabled state, and the clear control's gating, confirm and reach by
/// touch. `canvas_pane_test.dart` covers the header's own affordance into
/// the pane; this covers what the pane hands the bar.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_bar.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

CanvasBar _bar({
  CanvasTool tool = CanvasTool.pen,
  ValueChanged<CanvasTool>? onToolChanged,
  bool canUndo = false,
  VoidCallback? onUndo,
  bool canManage = false,
  ValueListenable<int>? objectCount,
  Future<void> Function()? onClear,
}) => CanvasBar(
  channelId: 'c1',
  onClose: () {},
  tool: tool,
  onToolChanged: onToolChanged ?? (_) {},
  canUndo: canUndo,
  onUndo: onUndo ?? () {},
  canManage: canManage,
  objectCount: objectCount ?? ValueNotifier<int>(3),
  onClear: onClear ?? () async {},
);

void main() {
  testWidgets('tapping the eraser calls onToolChanged with eraser', (
    tester,
  ) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(_bar(onToolChanged: (tool) => chosen = tool)),
    );

    await tester.tap(find.bySemanticsLabel('Eraser'));
    await tester.pump();

    expect(chosen, CanvasTool.eraser);
  });

  testWidgets('tapping the pen calls onToolChanged with pen', (tester) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(
        _bar(tool: CanvasTool.eraser, onToolChanged: (tool) => chosen = tool),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Pen'));
    await tester.pump();

    expect(chosen, CanvasTool.pen);
  });

  testWidgets('undo is disabled when canUndo is false', (tester) async {
    var undone = 0;
    await tester.pumpWidget(
      _wrap(_bar(canUndo: false, onUndo: () => undone++)),
    );

    final button = tester.widget<AppIconButton>(
      find.ancestor(
        of: find.bySemanticsLabel('Undo'),
        matching: find.byType(AppIconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(undone, 0);
  });

  testWidgets('undo fires onUndo when canUndo is true', (tester) async {
    var undone = 0;
    await tester.pumpWidget(_wrap(_bar(canUndo: true, onUndo: () => undone++)));

    await tester.tap(find.bySemanticsLabel('Undo'));
    await tester.pump();

    expect(undone, 1);
  });

  testWidgets('the overflow clear control is absent without MANAGE_CANVAS', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar(canManage: false)));
    expect(find.bySemanticsLabel('More canvas actions'), findsNothing);
  });

  testWidgets('the overflow clear control appears with MANAGE_CANVAS', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar(canManage: true)));
    expect(find.bySemanticsLabel('More canvas actions'), findsOneWidget);
  });

  testWidgets(
    'clearing goes through a menu, then a confirm naming the count, and '
    'only calls onClear once confirmed',
    (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        _wrap(
          _bar(
            canManage: true,
            objectCount: ValueNotifier<int>(42),
            onClear: () async => cleared++,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Clear canvas'), findsOneWidget);
      expect(cleared, 0, reason: 'opening the menu must not clear anything');

      await tester.tap(find.text('Clear canvas'));
      await tester.pumpAndSettle();

      expect(find.text('Clear this canvas?'), findsOneWidget);
      expect(
        find.textContaining('all 42 objects'),
        findsOneWidget,
        reason: 'the confirm must name the live count, not a stale one',
      );
      expect(cleared, 0);

      await tester.tap(find.text('Clear canvas').last);
      await tester.pumpAndSettle();

      expect(cleared, 1);
    },
  );

  testWidgets('cancelling the confirm never calls onClear', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      _wrap(_bar(canManage: true, onClear: () async => cleared++)),
    );

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear canvas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep canvas'));
    await tester.pumpAndSettle();

    expect(cleared, 0);
  });

  /// Every affordance this bar adds - pen, eraser, undo, the overflow, and
  /// the existing close - is a tap target, none of them keyboard-only.
  testWidgets('every new affordance is reachable by touch, at phone width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_bar(canManage: true, canUndo: true), width: 320),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in [
      'Pen',
      'Eraser',
      'Undo',
      'More canvas actions',
      'Close canvas',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '$label must be reachable at the narrowest supported width',
      );
    }
  });
}
