// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The eraser is on screen, inside its card, and hittable with no scroll at
/// the phone widths it used to sit past the strip's right edge. Asserted by
/// rect and by a real tap, with the pen selected (its caret widens the strip).
/// Undo, the overflow and close are in the header at these widths; the
/// call-screen geometry test covers them on the real shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'package:slimm_app/src/widgets/floating_dock_card.dart';

import 'support/canvas_call_dock_fixtures.dart';

const _tools = ['Pan', 'Pen', 'Note', 'Shape', 'Eraser'];
const _callControls = [
  'Mute',
  'Turn on camera',
  'Share a screen',
  'Leave call',
];
const _windowWidths = [360.0, 390.0, 430.0];
const _paneMargin = 24.0;

Rect _rect(WidgetTester tester, String label) =>
    tester.getRect(find.bySemanticsLabel(RegExp('^$label')).first);

void main() {
  for (final window in _windowWidths) {
    for (final withCall in [true, false]) {
      testWidgets(
        'every canvas control is on screen, inside the card and at least '
        '44dp, with no scrolling, at $window with${withCall ? '' : 'out'} a call',
        (tester) async {
          tester.view.physicalSize = Size(window, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var picked = <CanvasTool>[];
          await pumpCanvasCallDock(
            tester,
            withCall: withCall,
            canvas: buildCanvasDockData(
              canUndo: true,
              onToolChanged: picked.add,
            ),
            width: window - _paneMargin,
            touch: true,
            compact: true,
          );

          final cards = [
            for (final c in find.byType(FloatingDockCard).evaluate())
              tester.getRect(find.byWidget(c.widget)),
          ];
          expect(cards, hasLength(withCall ? 2 : 1));
          final screen = Offset.zero & Size(window, 900);
          final names = [..._tools, if (withCall) ..._callControls];
          for (final name in names) {
            final rect = _rect(tester, name);
            expect(screen.contains(rect.topLeft), isTrue, reason: name);
            expect(screen.contains(rect.bottomRight), isTrue, reason: name);
            expect(
              cards.any(
                (c) => c.contains(rect.topLeft) && c.contains(rect.bottomRight),
              ),
              isTrue,
              reason: '$name in a card',
            );
            expect(rect.width, greaterThanOrEqualTo(44), reason: '$name wide');
            expect(rect.height, greaterThanOrEqualTo(44), reason: '$name tall');
          }

          final rects = [for (final n in names) _rect(tester, n)];
          for (var i = 0; i < rects.length; i++) {
            for (var j = i + 1; j < rects.length; j++) {
              expect(
                rects[i].overlaps(rects[j]),
                isFalse,
                reason: '${names[i]} overlaps ${names[j]}',
              );
            }
          }

          for (final s in tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          )) {
            expect(s.position.maxScrollExtent, 0, reason: 'nothing to scroll');
          }

          await tester.tapAt(_rect(tester, 'Eraser').center);
          await tester.pump();
          expect(picked, [CanvasTool.eraser]);
        },
      );
    }
  }
}
