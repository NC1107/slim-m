// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `read_state.changed`: this account's read marker
/// moved on another device.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed read_state.changed frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'read_state.changed',
        'channel_id': 'c1',
        'last_read_seq': 7,
      }),
    );
    expect(event, isA<ReadStateChanged>());
    expect((event as ReadStateChanged).channelId, 'c1');
    expect(event.lastReadSeq, 7);
  });

  test('a frame missing last_read_seq is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({'type': 'read_state.changed', 'channel_id': 'c1'}),
    );
    expect(event, isNull);
  });
}
