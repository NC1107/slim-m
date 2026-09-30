// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The dock's own composition: which sections it draws for which inputs,
/// and the single-row-versus-stacked switch at the measured one-row width. Real hit
/// testing at phone width, with both sections present, is
/// `canvas_call_dock_touch_reach_test.dart` - this file covers what is
/// drawn, that file covers what a thumb can actually reach.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_tools_row.dart';
import 'package:slimm_app/src/screens/voice_call_controls.dart';
import 'package:slimm_app/src/widgets/floating_dock_card.dart';

import 'support/canvas_call_dock_fixtures.dart';

void main() {
  testWidgets('with only a call, the dock draws call controls and no '
      'canvas tools', (tester) async {
    await pumpCanvasCallDock(tester, withCall: true);

    expect(find.byType(CallControls), findsOneWidget);
    expect(find.byType(CanvasToolsRow), findsNothing);
  });

  testWidgets('with only a canvas open, the dock draws canvas tools and no '
      'call controls', (tester) async {
    await pumpCanvasCallDock(tester, canvas: buildCanvasDockData());

    expect(find.byType(CanvasToolsRow), findsOneWidget);
    expect(find.byType(CallControls), findsNothing);
  });

  testWidgets('with both, the dock draws both sections in one card', (
    tester,
  ) async {
    await pumpCanvasCallDock(
      tester,
      withCall: true,
      canvas: buildCanvasDockData(),
    );

    expect(find.byType(CallControls), findsOneWidget);
    expect(find.byType(CanvasToolsRow), findsOneWidget);
    expect(find.byType(FloatingDockCard), findsOneWidget);
  });

  testWidgets(
    'below the measured one-row width the dock stacks tools, edit and call as three rows',
    (tester) async {
      await pumpCanvasCallDock(
        tester,
        withCall: true,
        canvas: buildCanvasDockData(),
        width: 799,
      );

      final card = tester.widget<FloatingDockCard>(
        find.byType(FloatingDockCard),
      );
      expect(card.rows, hasLength(3));
    },
  );

  testWidgets('at the measured one-row width the two sections share one row', (
    tester,
  ) async {
    await pumpCanvasCallDock(
      tester,
      withCall: true,
      canvas: buildCanvasDockData(),
      width: 800,
    );

    final card = tester.widget<FloatingDockCard>(find.byType(FloatingDockCard));
    expect(card.rows, hasLength(1));
  });

  testWidgets('while the activity panel is open the tool cluster folds '
      'away but undo, the overflow and close stay', (tester) async {
    await pumpCanvasCallDock(
      tester,
      canvas: buildCanvasDockData(activityLogOpen: true),
    );

    expect(find.bySemanticsLabel('Pen'), findsNothing);
    expect(find.bySemanticsLabel('Undo'), findsOneWidget);
    expect(find.bySemanticsLabel('More canvas actions'), findsOneWidget);
    expect(find.bySemanticsLabel('Close canvas'), findsOneWidget);
  });
}
