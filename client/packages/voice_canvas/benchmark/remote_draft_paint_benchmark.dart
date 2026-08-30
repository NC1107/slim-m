// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What `RemoteDraftPainter.paint` actually costs against the 16.6ms frame
/// budget, at a shape the spike's own lesson says to check: viewport and
/// content shape, not object count, is where a canvas painter falls over.
///
/// A live drawer is rare (a handful at most in one voice call) but their
/// draft can grow long: at the client's own `maxStrokePreviewPointsPerFrame`
/// (20) every `strokePreviewSendInterval` (90ms), three seconds of
/// continuous drawing accumulates roughly 660 points on the receiving side,
/// since nothing here caps how long one in-flight draft may grow before its
/// `ended` frame finally arrives.
///
/// Run with `flutter test benchmark/remote_draft_paint_benchmark.dart`.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _frameBudgetMs = 16.6;

void main() {
  test('paint cost at realistic and stress-test draft counts', () {
    for (final drawers in [1, 6, 20]) {
      for (final pointsPerDraft in [8, 660]) {
        final us = _paintMicros(drawers, pointsPerDraft);
        final ms = us / 1000;
        final pct = (ms / _frameBudgetMs * 100).toStringAsFixed(1);
        // ignore: avoid_print
        print(
          '$drawers drawer(s) x $pointsPerDraft points: '
          '${ms.toStringAsFixed(3)}ms ($pct% of budget)',
        );
      }
    }
  });
}

double _paintMicros(int drawers, int pointsPerDraft) {
  final document = CanvasDocument()..setViewport(const Size(1400, 880));
  final drafts = RemoteStrokeDrafts();
  for (var d = 0; d < drawers; d++) {
    final points = <double>[
      for (var i = 0; i < pointsPerDraft; i++) ...[
        (i % 800).toDouble(),
        (i % 600).toDouble(),
      ],
    ];
    drafts.appendOrCreate(
      objectId: 'draft-$d',
      authorId: 'author-$d',
      points: points,
      colorIndex: d % 6,
    );
  }
  final painter = RemoteDraftPainter(
    drafts: drafts,
    document: document,
    colors: const [
      Color(0xFF000000),
      Color(0xFF111111),
      Color(0xFF222222),
      Color(0xFF333333),
      Color(0xFF444444),
      Color(0xFF555555),
    ],
  );

  void paintOnce() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(1400, 880));
    recorder.endRecording().dispose();
  }

  // Warm up, then take the median of several batches, `_time`'s own shape.
  final warm = Stopwatch()..start();
  var ops = 0;
  while (warm.elapsedMicroseconds < 60000) {
    paintOnce();
    ops++;
  }
  warm.stop();
  final batch = (10000 / (warm.elapsedMicroseconds / ops)).ceil().clamp(
        1,
        1 << 16,
      );

  final samples = <double>[];
  for (var t = 0; t < 7; t++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < batch; i++) {
      paintOnce();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds / batch);
  }
  samples.sort();

  drafts.dispose();
  document.dispose();
  return samples[samples.length ~/ 2];
}
