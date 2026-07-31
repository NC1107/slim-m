// SPDX-License-Identifier: Apache-2.0
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

CanvasStrokeInput horizontalStroke(
  String id, {
  double y = 0,
  int zIndex = 0,
  double width = 3,
}) =>
    CanvasStrokeInput(
      id: id,
      seq: zIndex,
      zIndex: zIndex,
      x: 0,
      y: y,
      w: 100,
      h: 0,
      points: const [0, 0, 100, 0],
      width: width,
      colorKey: 'annotation',
    );

void main() {
  test('a point on the line is a hit', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a'))
      ..refresh();

    expect(hitTestStroke(document, const Offset(50, 0)), 'a');
  });

  test('a point well past the tolerance is not a hit', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a', width: 2))
      ..refresh();

    expect(hitTestStroke(document, const Offset(50, 40), slop: 4), isNull);
  });

  test('a point just inside width/2 + slop is a hit, just outside is not', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a', width: 2))
      ..refresh();

    // tolerance = width / 2 + slop = 1 + 4 = 5.
    expect(hitTestStroke(document, const Offset(50, 4.9), slop: 4), 'a');
    expect(hitTestStroke(document, const Offset(50, 5.1), slop: 4), isNull);
  });

  test('the topmost stroke wins when two overlap', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('under', zIndex: 1))
      ..applyPlaced(horizontalStroke('over', zIndex: 2))
      ..refresh();

    expect(hitTestStroke(document, const Offset(50, 0)), 'over');
  });

  test('a removed stroke is never hit', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a'))
      ..refresh();
    expect(hitTestStroke(document, const Offset(50, 0)), 'a');

    document
      ..removeObject('a')
      ..refresh();
    expect(hitTestStroke(document, const Offset(50, 0)), isNull);
  });

  test('a killed (never-landed) stroke is never hit', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a'))
      ..refresh();
    expect(hitTestStroke(document, const Offset(50, 0)), 'a');

    document
      ..kill('a')
      ..refresh();
    expect(hitTestStroke(document, const Offset(50, 0)), isNull);
  });

  test('allowed skips a disallowed candidate for the one behind it', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('foreign', zIndex: 2))
      ..applyPlaced(horizontalStroke('mine', zIndex: 1))
      ..refresh();

    expect(hitTestStroke(document, const Offset(50, 0)), 'foreign');
    expect(
      hitTestStroke(
        document,
        const Offset(50, 0),
        allowed: (stroke) => stroke.id == 'mine',
      ),
      'mine',
    );
  });

  test('allowed refusing every candidate is a miss, not the nearest one', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(horizontalStroke('a'))
      ..refresh();

    expect(
      hitTestStroke(document, const Offset(50, 0), allowed: (_) => false),
      isNull,
    );
  });

  test('a single-point stroke is hit by proximity to that point', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(
        CanvasStrokeInput(
          id: 'dot',
          seq: 1,
          zIndex: 1,
          x: 10,
          y: 10,
          w: 0,
          h: 0,
          points: const [0, 0],
          width: 2,
          colorKey: 'annotation',
        ),
      )
      ..refresh();

    expect(hitTestStroke(document, const Offset(11, 11)), 'dot');
    expect(hitTestStroke(document, const Offset(200, 200)), isNull);
  });
}
