// SPDX-License-Identifier: Apache-2.0
/// The overflow's "Hide/Show my camera bubble" item: split out of
/// `canvas_bar_test.dart` once this fix pushed that file past the 500-line
/// hard limit, the same reason `canvas_bar_shape_kind_test.dart` and
/// `canvas_bar_touch_reach_test.dart` already split their own concerns out.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_bar_fixtures.dart';

void main() {
  testWidgets(
    'the toggle is absent when the caller is not on this channel\'s call '
    'at all',
    (tester) async {
      await tester.pumpWidget(
        wrapCanvasBar(buildCanvasBar(hasSelfBubble: false)),
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
        wrapCanvasBar(
          buildCanvasBar(
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
      wrapCanvasBar(
        buildCanvasBar(hasSelfBubble: true, selfBubbleHidden: true),
      ),
    );

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.text('Show my camera bubble'), findsOneWidget);
    expect(find.text('Hide my camera bubble'), findsNothing);
  });
}
