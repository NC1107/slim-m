// SPDX-License-Identifier: Apache-2.0
/// [ServerEvent.parse] for `member.restored` - the mirror of
/// `member.removed`, added so a remove-then-restore reaches already-open
/// clients instead of waiting for an unrelated refetch.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed member.restored frame', () {
    final event = ServerEvent.parse(
      jsonEncode({'type': 'member.restored', 'user_id': 'user-1'}),
    );
    expect(event, isA<MemberRestored>());
    expect((event as MemberRestored).userId, 'user-1');
  });

  test('a frame missing user_id is ignored, not thrown', () {
    final event = ServerEvent.parse(jsonEncode({'type': 'member.restored'}));
    expect(event, isNull);
  });
}
