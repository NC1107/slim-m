// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Remote cursors gliding between the ~80ms-apart frames the wire delivers,
/// instead of stepping: the model's interpolation, the retarget that must
/// continue from the in-flight position rather than jumping, and the painter
/// actually drawing the interpolated point.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _glide = Duration(milliseconds: 80);
final _t0 = DateTime(2026, 1, 1);

CanvasCursors _gliding() {
  final cursors = CanvasCursors();
  cursors.upsert(id: 'u', x: 0, y: 0, label: '', colorIndex: 0, now: _t0);
  cursors.upsert(
    id: 'u',
    x: 100,
    y: 0,
    label: '',
    colorIndex: 0,
    now: _t0,
    glide: _glide,
  );
  return cursors;
}

void main() {
  test('a cursor is midway through its glide midway through the window', () {
    final cursors = _gliding();
    addTearDown(cursors.dispose);
    final cursor = cursors.all.single;

    expect(
      cursor.positionAt(_t0.add(const Duration(milliseconds: 40)), _glide),
      const Offset(50, 0),
    );
    expect(
      cursor.positionAt(_t0.add(const Duration(milliseconds: 80)), _glide),
      const Offset(100, 0),
    );
    expect(cursor.glidingAt(_t0.add(const Duration(milliseconds: 40)), _glide),
        isTrue);
    expect(cursor.glidingAt(_t0.add(const Duration(milliseconds: 80)), _glide),
        isFalse);
  });

  test('a retarget mid-glide continues from the in-flight position', () {
    final cursors = _gliding();
    addTearDown(cursors.dispose);

    cursors.upsert(
      id: 'u',
      x: 100,
      y: 100,
      label: '',
      colorIndex: 0,
      now: _t0.add(const Duration(milliseconds: 40)),
      glide: _glide,
    );
    final cursor = cursors.all.single;
    // No jump: the new glide starts where the old one visibly was.
    expect(cursor.fromX, 50);
    expect(cursor.fromY, 0);
    expect(
      cursor.positionAt(_t0.add(const Duration(milliseconds: 40)), _glide),
      const Offset(50, 0),
    );
  });

  test('a first-ever frame appears at its target, never gliding in', () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    cursors.upsert(
      id: 'u',
      x: 70,
      y: 30,
      label: '',
      colorIndex: 0,
      now: _t0,
      glide: _glide,
    );
    expect(cursors.all.single.positionAt(_t0, _glide), const Offset(70, 30));
    expect(cursors.glidingAt(_t0, _glide), isFalse);
  });

  test('a zero glide answers the target, which is the reduce-motion path', () {
    final cursors = _gliding();
    addTearDown(cursors.dispose);
    expect(
      cursors.all.single.positionAt(_t0, Duration.zero),
      const Offset(100, 0),
    );
  });

  test('the painter draws the interpolated point, not the raw target',
      () async {
    final cursors = _gliding();
    addTearDown(cursors.dispose);
    final document = CanvasDocument()..setViewport(const Size(300, 100));
    addTearDown(document.dispose);

    final painter = CursorPainter(
      cursors: cursors,
      document: document,
      colors: const [Color(0xFFFF0000)],
      glide: _glide,
      now: () => _t0.add(const Duration(milliseconds: 40)),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(300, 100));
    final image = await recorder.endRecording().toImage(300, 100);
    final bytes = (await image.toByteData())!;

    int alphaAt(int x, int y) => bytes.getUint8((y * 300 + x) * 4 + 3);
    // The glyph hangs down-right of its point; sample inside each candidate.
    int inkNear(int x) {
      var ink = 0;
      for (var dx = 0; dx < 12; dx++) {
        for (var dy = 0; dy < 17; dy++) {
          if (alphaAt(x + dx, dy) > 0) ink++;
        }
      }
      return ink;
    }

    expect(inkNear(50), greaterThan(0));
    expect(inkNear(100), 0);
  });
}
