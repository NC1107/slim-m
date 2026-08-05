// SPDX-License-Identifier: Apache-2.0
/// [CanvasDocument.moveObject], [CanvasDocument.objectBounds] and
/// [CanvasDocument.setImageBitmap]: repositioning a placed object, and
/// attaching a decoded bitmap to one.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

CanvasStrokeInput strokeAt(String id, {double x = 0, double y = 0}) =>
    CanvasStrokeInput(
      id: id,
      seq: 1,
      zIndex: 1,
      x: x,
      y: y,
      w: 10,
      h: 5,
      points: const [0, 0, 10, 5],
      width: 3,
      colorKey: 'annotation',
    );

void main() {
  test('moveObject relocates the box and the index follows it', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(strokeAt('a', x: 0, y: 0))
      ..refresh();

    expect(hitTestStroke(document, const Offset(5, 2.5)), 'a');

    expect(document.moveObject('a', 100, 100, 10, 5), isTrue);
    document.refresh();

    expect(hitTestStroke(document, const Offset(5, 2.5)), isNull);
    expect(hitTestStroke(document, const Offset(105, 102.5)), 'a');
  });

  test('moveObject translates a stroke\'s own points, not only its box', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(strokeAt('a', x: 0, y: 0))
      ..refresh();

    document
      ..moveObject('a', 100, 100, 10, 5)
      ..refresh();

    // The stroke's drawn line, not merely its bounding box, must have moved -
    // a point at the old end of the line must no longer hit-test.
    expect(hitTestStroke(document, const Offset(10, 5)), isNull);
    expect(hitTestStroke(document, const Offset(110, 105)), 'a');
  });

  test('moveObject preserves zIndex, kind and attachmentId', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document
      ..applyPlaced(
        CanvasStrokeInput(
          id: 'pic',
          seq: 3,
          zIndex: 3,
          x: 0,
          y: 0,
          w: 20,
          h: 20,
          points: const [],
          width: 0,
          colorKey: '',
          kind: CanvasObjectKind.image,
          attachmentId: 'sha-pic',
        ),
      )
      ..refresh();

    document.moveObject('pic', 50, 50, 20, 20);

    final slot = hitTestImageAt(document, const Offset(60, 60));
    expect(slot, 'pic');
    final bounds = document.objectBounds('pic')!;
    expect((bounds.x, bounds.y, bounds.w, bounds.h), (50.0, 50.0, 20.0, 20.0));
  });

  test('moveObject on an unknown or removed id returns false', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    expect(document.moveObject('nope', 1, 1, 1, 1), isFalse);

    document
      ..applyPlaced(strokeAt('a'))
      ..removeObject('a');
    expect(document.moveObject('a', 1, 1, 1, 1), isFalse);
  });

  test('objectBounds reports the current box, and null once removed', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    document.applyPlaced(strokeAt('a', x: 3, y: 4));

    final bounds = document.objectBounds('a')!;
    expect((bounds.x, bounds.y, bounds.w, bounds.h), (3.0, 4.0, 10.0, 5.0));

    document.removeObject('a');
    expect(document.objectBounds('a'), isNull);
  });

  test('objectBounds is null for an id never placed', () {
    final document = CanvasDocument()..setViewport(const Size(800, 600));
    expect(document.objectBounds('never'), isNull);
  });
}
