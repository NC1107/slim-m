// SPDX-License-Identifier: Apache-2.0
/// A tool switch is the one thing allowed to change the surface's cursor -
/// see [CanvasSurface]'s own doc for why a per-hover cursor is not.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Future<MouseCursor?> _cursorAfter(
  WidgetTester tester,
  CanvasDocument document, {
  required CanvasTool tool,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CanvasSurface(
        document: document,
        ink: const Color(0xFFE86A5C),
        onStroke: (_) {},
        tool: tool,
        enabled: enabled,
      ),
    ),
  );
  await tester.pump();
  const pointerId = 1;
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: pointerId,
  );
  await gesture.addPointer(
    location: tester.getCenter(find.byType(CanvasSurface)),
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
    pointerId,
  );
}

void main() {
  testWidgets('the pen shows a precise cursor', (tester) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    expect(
      await _cursorAfter(tester, document, tool: CanvasTool.pen),
      SystemMouseCursors.precise,
    );
  });

  testWidgets('the eraser shows a precise cursor too', (tester) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    expect(
      await _cursorAfter(tester, document, tool: CanvasTool.eraser),
      SystemMouseCursors.precise,
    );
  });

  testWidgets('the move tool shows a grab cursor', (tester) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    expect(
      await _cursorAfter(tester, document, tool: CanvasTool.select),
      SystemMouseCursors.grab,
    );
  });

  testWidgets('a disabled surface shows the plain arrow regardless of tool', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    expect(
      await _cursorAfter(
        tester,
        document,
        tool: CanvasTool.select,
        enabled: false,
      ),
      SystemMouseCursors.basic,
    );
  });
}
