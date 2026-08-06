// SPDX-License-Identifier: Apache-2.0
/// The mouse wheel and trackpad-scroll half of [CanvasSurface]'s camera
/// controls - `_signal`'s own handling of `PointerScrollEvent`. Split out
/// from `canvas_surface_test.dart` since nothing there touched it: there was
/// no coverage at all for this path before the mouse-pan fix it accompanies.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  testWidgets(
    'a real mouse wheel notch (dy only) pans vertically, unmodified',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            onStroke: (_) {},
          ),
        ),
      );
      await tester.pump();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(50, 50)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
      await tester.pump();

      expect(document.camera.x, 0);
      expect(document.camera.y, 40);
    },
  );

  testWidgets(
    'a trackpad swipe (dx and dy both set) pans in both axes, unmodified',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            onStroke: (_) {},
          ),
        ),
      );
      await tester.pump();

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.hover(const Offset(50, 50)));
      await tester.sendEventToBinding(trackpad.scroll(const Offset(25, 40)));
      await tester.pump();

      expect(document.camera.x, 25);
      expect(document.camera.y, 40);
    },
  );

  testWidgets('Ctrl+wheel zooms about the pointer rather than panning', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CanvasSurface(
          document: document,
          ink: const Color(0xFFE86A5C),
          gridLine: const Color(0xFF303030),
          onStroke: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(Offset.zero));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -40)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(document.camera.zoom, greaterThan(1));
    expect(
      document.camera.x,
      0,
      reason: 'zooming about the same point the camera already reads at '
          'the world origin moves nothing, unlike a pan',
    );
    expect(document.camera.y, 0);
  });

  /// The regression this whole file exists for: a real mouse wheel never
  /// carries a horizontal delta in `dx`, so the pre-fix code (`dx = shift ?
  /// event.scrollDelta.dy : event.scrollDelta.dx`) read the platform's own
  /// swapped value correctly when the platform delivers it in `dy`, but
  /// answered zero on a platform that swaps a shifted wheel's delta into
  /// `dx` *before* Flutter ever sees it - the same "only ever reports dy"
  /// shape as the unmodified case, just inverted. This drives both delivery
  /// shapes and asserts both pan horizontally.
  testWidgets(
    'Shift+wheel pans horizontally whichever axis the platform delivers the delta on',
    (tester) async {
      for (final delta in [const Offset(0, 40), const Offset(40, 0)]) {
        final document = CanvasDocument();
        addTearDown(document.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: CanvasSurface(
              document: document,
              ink: const Color(0xFFE86A5C),
              gridLine: const Color(0xFF303030),
              onStroke: (_) {},
            ),
          ),
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(mouse.hover(const Offset(50, 50)));
        await tester.sendEventToBinding(mouse.scroll(delta));
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

        expect(document.camera.x, 40, reason: 'delta: $delta');
        expect(document.camera.y, 0, reason: 'delta: $delta');
      }
    },
  );
}
