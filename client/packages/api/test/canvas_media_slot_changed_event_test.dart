// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `canvas.media_slot.changed` - decision 0010's
/// reversal, the live frame a media tile's shared position, size, lock and
/// depth now reach every viewer through.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed canvas.media_slot.changed frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.media_slot.changed',
        'channel_id': 'chan-1',
        'kind': 'screen',
        'user_id': 'user-1',
        'x': 12.5,
        'y': -4.0,
        'w': 360.0,
        'h': 203.0,
        'locked': true,
        'sent_to_back': false,
      }),
    );

    expect(event, isA<CanvasMediaSlotChanged>());
    final changed = event as CanvasMediaSlotChanged;
    expect(changed.channelId, 'chan-1');
    expect(changed.kind, 'screen');
    expect(changed.userId, 'user-1');
    expect(changed.x, 12.5);
    expect(changed.y, -4.0);
    expect(changed.w, 360.0);
    expect(changed.h, 203.0);
    expect(changed.locked, isTrue);
    expect(changed.sentToBack, isFalse);
  });

  test('a frame missing a required field is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'canvas.media_slot.changed',
        'channel_id': 'chan-1',
        'kind': 'camera',
        'user_id': 'user-1',
        'x': 1.0,
        'y': 1.0,
        'w': 1.0,
        'h': 1.0,
        'locked': false,
        // sent_to_back missing
      }),
    );

    expect(event, isNull);
  });

  test('CanvasMediaSlot.fromJson round-trips a REST slot row', () {
    final slot = CanvasMediaSlot.fromJson({
      'kind': 'camera',
      'user_id': 'user-2',
      'x': 5.0,
      'y': 6.0,
      'w': 220.0,
      'h': 160.0,
      'locked': false,
      'sent_to_back': true,
      'updated_at': 1000,
    });

    expect(slot.kind, 'camera');
    expect(slot.userId, 'user-2');
    expect(slot.x, 5.0);
    expect(slot.y, 6.0);
    expect(slot.w, 220.0);
    expect(slot.h, 160.0);
    expect(slot.locked, isFalse);
    expect(slot.sentToBack, isTrue);
    expect(slot.updatedAt, 1000);
  });
}
