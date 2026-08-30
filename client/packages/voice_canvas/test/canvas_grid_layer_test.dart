// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A regression guard for the grid never rendering once it was pulled out of
/// `CanvasSurface`'s own `Stack(fit: StackFit.expand)` into its own widget -
/// see `canvas_grid_layer.dart`'s own doc for the mechanism.
///
/// `canvas_presence_depth_test.dart` (the app package) already asserts this
/// widget's position in the assembled pane's `Stack`, but a widget can be in
/// the right place in the tree and still paint nothing: a bare `CustomPaint`
/// with no child collapses to `Size.zero` under loose constraints, and
/// nothing about being the first child of a `Stack` prevents that. This test
/// checks the thing ordering cannot see - the render object's own size -
/// against the exact shape the real bug had: a plain `Stack` with no `fit`
/// set, the default every ordinary `Stack()` call carries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  testWidgets(
    'CanvasGridLayer fills its Stack even when that Stack never sets '
    'fit: StackFit.expand',
    (tester) async {
      final document = CanvasDocument()..setViewport(const Size(400, 300));
      addTearDown(document.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              // The plain no-fit Stack every real call site uses, as shipped.
              child: Stack(
                children: [
                  CanvasGridLayer(
                    document: document,
                    line: const Color(0xFF888888),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final box = tester.renderObject<RenderBox>(
        find.byType(CanvasGridLayer),
      );
      expect(
        box.size,
        const Size(400, 300),
        reason: 'a zero-size render object never calls its painter\'s paint(), '
            'so the grid silently never draws a line',
      );
    },
  );
}
