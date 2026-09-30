// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The live stroke preview follows the armed pen: a colour or width picked
/// after the surface first built must reach the next stroke, not the first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/src/canvas_live_painters.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget _surface(CanvasDocument document, {Color? penInk, double width = 3}) =>
    MaterialApp(
      home: CanvasSurface(
        document: document,
        ink: const Color(0xFFE86A5C),
        penInk: penInk,
        strokeWidth: width,
        onStroke: (_) {},
      ),
    );

DraftPainter _draftPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<DraftPainter>()
    .single;

void main() {
  testWidgets('changing the pen colour and width reaches the draft painter', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    await tester.pumpWidget(_surface(document));
    expect(_draftPainter(tester).ink, const Color(0xFFE86A5C));
    expect(_draftPainter(tester).width, 3);

    await tester.pumpWidget(
      _surface(document, penInk: const Color(0xFF5B8FD6), width: 6),
    );
    expect(_draftPainter(tester).ink, const Color(0xFF5B8FD6));
    expect(_draftPainter(tester).width, 6);
  });
}
