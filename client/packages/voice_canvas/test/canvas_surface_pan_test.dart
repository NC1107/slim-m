// SPDX-License-Identifier: Apache-2.0
/// Grab-to-pan: holding the middle mouse button and dragging moves the
/// camera regardless of the active tool, without disturbing whatever that
/// tool was mid-way through - see `_beginPan`/`_interruptForPan`'s own docs.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  testWidgets('a middle-button drag pans the camera', (tester) async {
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

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(const Offset(100, 100), buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(pointer.move(const Offset(60, 130)));
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(
      document.camera.x,
      40,
      reason: 'dragging left should move the camera the opposite way, '
          'so content follows the hand',
    );
    expect(document.camera.y, -30);
  });

  testWidgets('a middle-button drag never places ink for the active tool', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    var strokes = 0;
    final erased = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CanvasSurface(
          document: document,
          ink: const Color(0xFFE86A5C),
          gridLine: const Color(0xFF303030),
          onStroke: (_) => strokes++,
          onErase: erased.add,
        ),
      ),
    );
    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(const Offset(20, 20), buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(pointer.move(const Offset(80, 80)));
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(strokes, 0);
    expect(erased, isEmpty);
  });

  testWidgets(
    'the grab button joining an in-progress pen draft cancels it and pans instead',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      var strokes = 0;
      var draftEnded = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            onStroke: (_) => strokes++,
            onDraftEnded: () => draftEnded++,
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(20, 20), buttons: kPrimaryButton),
      );
      await tester.sendEventToBinding(pointer.move(const Offset(40, 40)));
      expect(draftEnded, 0, reason: 'the pen draft is still under way');

      await tester.sendEventToBinding(
        pointer.move(
          const Offset(70, 60),
          buttons: kPrimaryButton | kMiddleMouseButton,
        ),
      );
      expect(
        draftEnded,
        1,
        reason: 'the grab button joining cancels the draft immediately',
      );

      await tester.sendEventToBinding(pointer.move(const Offset(100, 90)));
      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(strokes, 0, reason: 'a cancelled draft never becomes a stroke');
      expect(draftEnded, 1, reason: 'only the cancellation fired it');
      expect(
        document.camera.x,
        lessThan(0),
        reason: 'the drag after the grab joined should still have panned',
      );
    },
  );

  testWidgets(
    'the grab button joining an in-progress erase drag flushes it through onEraseEnd',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      final erased = <Offset>[];
      var ends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            tool: CanvasTool.eraser,
            onStroke: (_) {},
            onErase: erased.add,
            onEraseEnd: () => ends++,
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(20, 20), buttons: kPrimaryButton),
      );
      await tester.sendEventToBinding(pointer.move(const Offset(40, 40)));
      expect(ends, 0);

      await tester.sendEventToBinding(
        pointer.move(
          const Offset(70, 60),
          buttons: kPrimaryButton | kMiddleMouseButton,
        ),
      );

      expect(
        ends,
        1,
        reason: 'the grab joining flushes the drag as one removal',
      );
      expect(erased, [const Offset(20, 20), const Offset(40, 40)]);

      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(ends, 1,
          reason: 'the pointer finally lifting must not flush a second time');
    },
  );

  testWidgets(
    'the grab button joining an in-progress select drag flushes it through onSelectEnd',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      var ends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            tool: CanvasTool.select,
            onStroke: (_) {},
            onSelectEnd: () => ends++,
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(20, 20), buttons: kPrimaryButton),
      );
      await tester.sendEventToBinding(pointer.move(const Offset(40, 40)));
      await tester.sendEventToBinding(
        pointer.move(
          const Offset(70, 60),
          buttons: kPrimaryButton | kMiddleMouseButton,
        ),
      );

      expect(ends, 1);

      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(ends, 1, reason: 'no second onSelectEnd once the pan ends');
    },
  );

  testWidgets(
    'a disabled surface still pans with the grab button, the same as the wheel already does',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(
            document: document,
            ink: const Color(0xFFE86A5C),
            gridLine: const Color(0xFF303030),
            enabled: false,
            onStroke: (_) {},
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(20, 20), buttons: kMiddleMouseButton),
      );
      await tester.sendEventToBinding(pointer.move(const Offset(60, 20)));
      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(document.camera.x, -40);
    },
  );

  testWidgets(
      'the cursor shows grabbing while panning, and the prior tool cursor after',
      (
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

    const pointerId = 1;
    final pointer = TestPointer(pointerId, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(50, 50)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
        pointerId,
      ),
      SystemMouseCursors.precise,
      reason: 'the pen tool cursor before any grab starts',
    );

    await tester.sendEventToBinding(
      pointer.down(const Offset(50, 50), buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(pointer.move(const Offset(80, 80)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
        pointerId,
      ),
      SystemMouseCursors.grabbing,
    );

    await tester.sendEventToBinding(pointer.up());
    await tester.sendEventToBinding(pointer.hover(const Offset(80, 80)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
        pointerId,
      ),
      SystemMouseCursors.precise,
      reason: 'the tool cursor returns once the grab ends',
    );
  });
}
