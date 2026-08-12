// SPDX-License-Identifier: Apache-2.0
/// The surface's glide driver: frames are scheduled only while a cursor is
/// actually mid-glide, stop once every glide lands, and are never scheduled
/// at all for a zero (reduce-motion, or unwired) glide.
///
/// The upserts plant `movedAt` a second into the future or the past instead
/// of using the real now: the driver reads the wall clock, and a test that
/// raced the real 80ms window would flake on a loaded runner.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget _surface(
        CanvasCursors cursors, CanvasDocument document, Duration glide) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: CanvasSurface(
        document: document,
        ink: const Color(0xFF000000),
        onStroke: (_) {},
        cursors: cursors,
        cursorColors: const [Color(0xFFFF0000)],
        cursorGlide: glide,
      ),
    );

void _move(CanvasCursors cursors, DateTime at) {
  cursors.upsert(id: 'u', x: 0, y: 0, label: '', colorIndex: 0, now: at);
  cursors.upsert(
    id: 'u',
    x: 100,
    y: 0,
    label: '',
    colorIndex: 0,
    now: at,
    glide: const Duration(milliseconds: 80),
  );
}

void main() {
  testWidgets('a glide in flight keeps frames coming', (tester) async {
    final cursors = CanvasCursors();
    final document = CanvasDocument();
    addTearDown(cursors.dispose);
    addTearDown(document.dispose);
    await tester.pumpWidget(
      _surface(cursors, document, const Duration(milliseconds: 80)),
    );
    await tester.pump();

    _move(cursors, DateTime.now().add(const Duration(seconds: 1)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Unmounting stops and disposes the ticker cleanly mid-glide.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a landed glide stops asking for frames', (tester) async {
    final cursors = CanvasCursors();
    final document = CanvasDocument();
    addTearDown(cursors.dispose);
    addTearDown(document.dispose);
    await tester.pumpWidget(
      _surface(cursors, document, const Duration(milliseconds: 80)),
    );
    await tester.pump();

    _move(cursors, DateTime.now().subtract(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a zero glide never starts the ticker at all', (tester) async {
    final cursors = CanvasCursors();
    final document = CanvasDocument();
    addTearDown(cursors.dispose);
    addTearDown(document.dispose);
    await tester.pumpWidget(_surface(cursors, document, Duration.zero));
    await tester.pump();

    _move(cursors, DateTime.now().add(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
