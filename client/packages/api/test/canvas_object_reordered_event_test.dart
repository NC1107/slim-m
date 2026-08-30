// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `canvas.object.reordered`, and
/// [CanvasOp.fromJson]'s `reorder` case in the catch-up feed - the two wire
/// shapes a restacked canvas object can arrive through. Mirrors
/// `canvas_object_moved_event_test.dart`'s own coverage of `move`.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed canvas.object.reordered frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.object.reordered',
        'channel_id': 'chan-1',
        'seq': 4,
        'op_id': 'op-1',
        'object_id': 'obj-1',
        'z_index': 500,
      }),
    );

    expect(event, isA<CanvasObjectReordered>());
    final reordered = event as CanvasObjectReordered;
    expect(reordered.channelId, 'chan-1');
    expect(reordered.seq, 4);
    expect(reordered.opId, 'op-1');
    expect(reordered.objectId, 'obj-1');
    expect(reordered.zIndex, 500);
  });

  test('a negative z_index (send to back) is accepted', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.object.reordered',
        'channel_id': 'chan-1',
        'seq': 4,
        'op_id': 'op-1',
        'object_id': 'obj-1',
        'z_index': -100,
      }),
    );

    expect((event as CanvasObjectReordered).zIndex, -100);
  });

  test('a frame missing a required field is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.object.reordered',
        'channel_id': 'chan-1',
        'seq': 4,
        'op_id': 'op-1',
        // object_id missing
        'z_index': 1,
      }),
    );

    expect(event, isNull);
  });

  test('a canvas op feed row of kind reorder parses to CanvasReorderOp', () {
    final op = CanvasOp.fromJson({
      'seq': 7,
      'id': 'op-2',
      'actor_id': 'user-1',
      'created_at': 1000,
      'kind': 'reorder',
      'object_id': 'obj-2',
      'z_index': 42,
    });

    expect(op, isA<CanvasReorderOp>());
    final reorder = op as CanvasReorderOp;
    expect(reorder.objectId, 'obj-2');
    expect(reorder.zIndex, 42);
  });
}
