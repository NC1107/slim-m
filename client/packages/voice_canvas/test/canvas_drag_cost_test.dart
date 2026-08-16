// SPDX-License-Identifier: Apache-2.0
/// What one drag costs the document.
///
/// A drag calls [CanvasDocument.moveObject] once per pointer event - a few
/// hundred times for one object dragged across a screen. This pins what that
/// must not do: hand out a fresh grid slot each time, reallocate the point
/// array each time, or replace the object identity each time.
///
/// The slot count is the sharpest of the three because the cost does not end
/// with the gesture. The grid never reuses a parked slot, so a slot leaked
/// per pointer event is leaked for the session, and every later linear cull
/// walks it (`spatial_grid.dart`'s own note: a parked slot makes the grid
/// branch cheaper and the linear branch no cheaper).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

CanvasStrokeInput _stroke(String id) => CanvasStrokeInput(
      id: id,
      x: 0,
      y: 0,
      w: 10,
      h: 10,
      points: Float32List.fromList(<double>[0, 0, 10, 10]),
      width: 2,
      colorKey: 'ink',
      zIndex: 0,
      seq: 1,
    );

void main() {
  test('a drag hands out no new slots, however long it runs', () {
    final doc = CanvasDocument()..applyPlaced(_stroke('a'));
    final before = doc.scene.slotCount;

    for (var i = 1; i <= 200; i++) {
      expect(doc.moveObject('a', i.toDouble(), i.toDouble(), 10, 10), isTrue);
    }

    expect(
      doc.scene.slotCount,
      before,
      reason: 'one slot per pointer event is leaked for the session, since the '
          'grid never reuses a parked one',
    );
    expect(doc.scene.objectCount, 1);
    doc.dispose();
  });

  test('a drag keeps the object identity it started with', () {
    final doc = CanvasDocument()..applyPlaced(_stroke('a'));
    final slot = doc.slotOf('a')!;
    final identity = doc.strokeAt(slot);

    doc.moveObject('a', 40, 50, 10, 10);

    expect(
      doc.slotOf('a'),
      slot,
      reason: 'a move repositions an object; it does not replace it',
    );
    expect(identical(doc.strokeAt(slot), identity), isTrue);
    doc.dispose();
  });

  test('a drag reuses the point array rather than reallocating it', () {
    final doc = CanvasDocument()..applyPlaced(_stroke('a'));
    final points = doc.strokeAt(doc.slotOf('a')!).points;

    doc.moveObject('a', 7, 11, 10, 10);

    expect(
      identical(doc.strokeAt(doc.slotOf('a')!).points, points),
      isTrue,
      reason: 'a fresh Float32List per pointer event is the drag-time garbage '
          'this exists to keep out',
    );
    doc.dispose();
  });

  /// The behaviour the optimisation must not change.
  test('a moved object still hit-tests and bounds where it was put', () {
    final doc = CanvasDocument()..applyPlaced(_stroke('a'));

    doc.moveObject('a', 100, 200, 10, 10);

    final bounds = doc.objectBounds('a');
    expect(bounds, isNotNull);
    expect(bounds!.x, 100);
    expect(bounds.y, 200);
    expect(bounds.w, 10);
    expect(bounds.h, 10);

    final moved = doc.strokeAt(doc.slotOf('a')!);
    expect(
      moved.points[0],
      100,
      reason: 'runtime points are absolute world coordinates, so they travel '
          'with the object or hit testing goes on answering at the old place',
    );
    expect(moved.points[1], 200);
    expect(moved.points[2], 110);
    expect(moved.points[3], 210);
    doc.dispose();
  });

  test('moving an unknown or removed object is refused, not a crash', () {
    final doc = CanvasDocument()..applyPlaced(_stroke('a'));
    expect(doc.moveObject('nobody', 1, 1, 1, 1), isFalse);
    doc.removeObject('a');
    expect(doc.moveObject('a', 1, 1, 1, 1), isFalse);
    doc.dispose();
  });
}
