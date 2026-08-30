// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The overflow's "Hide/Show my camera bubble" item: split out of
/// `canvas_tools_row_test.dart` for the same reason `canvas_tools_row_shape_
/// kind_test.dart` and `canvas_tools_row_touch_reach_test.dart` already
/// split their own concerns out. Ported from `canvas_bar_self_bubble_test
/// .dart`, unchanged in what it asserts, once the item's real home moved
/// from `CanvasBar` to `CanvasToolsRow`'s own overflow menu alongside the
/// rest of the dock's controls.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_tools_row_fixtures.dart';

void main() {
  testWidgets(
    'the toggle is absent when the caller is not on this channel\'s call '
    'at all',
    (tester) async {
      await tester.pumpWidget(
        wrapCanvasToolsRow(buildCanvasToolsRow(hasSelfBubble: false)),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();

      expect(find.text('Hide my camera bubble'), findsNothing);
      expect(find.text('Show my camera bubble'), findsNothing);
    },
  );

  testWidgets(
    'the overflow offers to hide or show the caller\'s own camera bubble '
    'while on the call, and its label says which',
    (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        wrapCanvasToolsRow(
          buildCanvasToolsRow(
            hasSelfBubble: true,
            onToggleSelfBubbleHidden: () => toggled++,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Hide my camera bubble'), findsOneWidget);
      expect(find.text('Show my camera bubble'), findsNothing);

      await tester.tap(find.text('Hide my camera bubble'));
      await tester.pump();
      expect(toggled, 1);
    },
  );

  testWidgets('the label flips once the bubble is hidden', (tester) async {
    await tester.pumpWidget(
      wrapCanvasToolsRow(
        buildCanvasToolsRow(hasSelfBubble: true, selfBubbleHidden: true),
      ),
    );

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.text('Show my camera bubble'), findsOneWidget);
    expect(find.text('Hide my camera bubble'), findsNothing);
  });
}
