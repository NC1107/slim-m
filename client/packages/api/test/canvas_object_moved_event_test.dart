// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `canvas.object.moved`, and [CanvasOp.fromJson]'s
/// `move` case in the catch-up feed - the two wire shapes a repositioned
/// canvas object can arrive through.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed canvas.object.moved frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.object.moved',
        'channel_id': 'chan-1',
        'seq': 4,
        'op_id': 'op-1',
        'object_id': 'obj-1',
        'x': 12.5,
        'y': -4.0,
        'w': 64.0,
        'h': 48.0,
      }),
    );

    expect(event, isA<CanvasObjectMoved>());
    final moved = event as CanvasObjectMoved;
    expect(moved.channelId, 'chan-1');
    expect(moved.seq, 4);
    expect(moved.opId, 'op-1');
    expect(moved.objectId, 'obj-1');
    expect(moved.x, 12.5);
    expect(moved.y, -4.0);
    expect(moved.w, 64.0);
    expect(moved.h, 48.0);
  });

  test('a frame missing a required field is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.object.moved',
        'channel_id': 'chan-1',
        'seq': 4,
        'op_id': 'op-1',
        'object_id': 'obj-1',
        'x': 1.0,
        'y': 1.0,
        // w missing
      }),
    );

    expect(event, isNull);
  });

  test('a canvas op feed row of kind move parses to CanvasMoveOp', () {
    final op = CanvasOp.fromJson({
      'seq': 7,
      'id': 'op-2',
      'actor_id': 'user-1',
      'created_at': 1000,
      'kind': 'move',
      'object_id': 'obj-2',
      'x': 1.0,
      'y': 2.0,
      'w': 3.0,
      'h': 4.0,
    });

    expect(op, isA<CanvasMoveOp>());
    final move = op as CanvasMoveOp;
    expect(move.objectId, 'obj-2');
    expect(move.x, 1.0);
    expect(move.y, 2.0);
    expect(move.w, 3.0);
    expect(move.h, 4.0);
  });
}
