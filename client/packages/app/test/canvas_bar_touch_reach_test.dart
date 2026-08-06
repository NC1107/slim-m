// SPDX-License-Identifier: Apache-2.0
/// The tool strip's own scroll behaviour at a phone width: a tool clipped
/// past the visible strip is not reachable by a bare tap, and the edge fade
/// is the only on-screen cue that more sits past the edge it fades toward.
/// Split out of `canvas_bar_test.dart` once this pushed it past the
/// 500-line hard limit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_bar.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'support/canvas_bar_fixtures.dart';

void main() {
  /// A tool clipped by the strip's own scroll viewport is not the same as
  /// a broken button: a bare tap misses it, at the exact offset the tool
  /// strip's own layout puts it at, until a real drag reveals it first -
  /// the same journey a thumb on a phone would need. Reproduces the report
  /// this pass found: at every real phone width, "Move" (the only route to
  /// select, resize, reorder or delete a placed object by touch) sat past
  /// this offset with nothing on screen saying so.
  testWidgets(
    'a clipped tool is unreachable by a bare tap, and reachable once the '
    'strip is dragged',
    (tester) async {
      CanvasTool? chosen;
      await tester.pumpWidget(
        wrapCanvasBar(
          buildCanvasBar(onToolChanged: (tool) => chosen = tool),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Move'), warnIfMissed: false);
      await tester.pump();
      expect(
        chosen,
        isNull,
        reason: 'a bare tap must not silently land on a clipped tool',
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-1000, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Move'));
      await tester.pump();
      expect(chosen, CanvasTool.select);
    },
  );

  /// The fade is the only on-screen cue that a tool sits past the visible
  /// strip; without it a clipped icon reads as a broken layout rather than
  /// an invitation to scroll. Present from the very first frame - the
  /// strip overflows before anyone has touched it - gone once nothing is
  /// left to reveal, and never present at all once the strip has room for
  /// every tool.
  testWidgets(
    'the tool strip fades its clipped edge, and only the edge with more to '
    'reveal',
    (tester) async {
      await tester.pumpWidget(wrapCanvasBar(buildCanvasBar(), width: 320));
      await tester.pumpAndSettle();
      expect(find.byKey(canvasBarLeadingFadeKey), findsNothing);
      expect(find.byKey(canvasBarTrailingFadeKey), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-40, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(canvasBarLeadingFadeKey), findsOneWidget);
      expect(find.byKey(canvasBarTrailingFadeKey), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-1000, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(canvasBarLeadingFadeKey), findsOneWidget);
      expect(find.byKey(canvasBarTrailingFadeKey), findsNothing);
    },
  );

  testWidgets('neither edge fades once the strip has room for every tool', (
    tester,
  ) async {
    await tester.pumpWidget(wrapCanvasBar(buildCanvasBar()));
    await tester.pumpAndSettle();

    expect(find.byKey(canvasBarLeadingFadeKey), findsNothing);
    expect(find.byKey(canvasBarTrailingFadeKey), findsNothing);
  });
}
