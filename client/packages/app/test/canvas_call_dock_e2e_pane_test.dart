// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The e2e harness taps the canvas at half its height
/// (`scripts/lib/e2e_canvas_shapes.py`), in a 795dp pane that stacks the dock.
/// That dock must stay in the lower half, or the harness taps the dock instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimm_app/src/widgets/floating_dock_card.dart';

import 'support/canvas_call_dock_fixtures.dart';

// The 1280dp e2e window less the channel rail and the members panel.
const _e2ePaneWidth = 795.0;
const _e2ePaneHeight = 721.0;
const _e2eTapFraction = 0.5;

void main() {
  testWidgets('the stacked dock in the e2e pane leaves the tap row clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpCanvasCallDock(
      tester,
      withCall: true,
      canvas: buildCanvasDockData(canUndo: true),
      width: _e2ePaneWidth,
    );

    final card = tester.getRect(find.byType(FloatingDockCard));
    final pan = tester.getRect(find.bySemanticsLabel(RegExp('^Pan')).first);
    final undo = tester.getRect(find.bySemanticsLabel(RegExp('^Undo')).first);
    expect(pan.bottom, lessThanOrEqualTo(undo.top), reason: 'the dock stacks');
    expect(
      card.height,
      lessThan(_e2ePaneHeight * (1 - _e2eTapFraction)),
      reason: 'a taller dock would cover where the e2e harness taps the canvas',
    );
    expect(
      find.bySemanticsLabel(RegExp('^Eraser')),
      findsOneWidget,
      reason: 'the e2e harness locates the dock by its eraser',
    );
  });
}
