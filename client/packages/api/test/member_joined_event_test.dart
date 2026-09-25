// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `member.joined`: a real join, so the roster no
/// longer has to infer one from a presence frame or a first message.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed member.joined frame', () {
    final event = ServerEvent.parse(
      jsonEncode({'type': 'member.joined', 'user_id': 'user-1'}),
    );
    expect(event, isA<MemberJoined>());
    expect((event as MemberJoined).userId, 'user-1');
  });

  test('a frame missing user_id is ignored, not thrown', () {
    final event = ServerEvent.parse(jsonEncode({'type': 'member.joined'}));
    expect(event, isNull);
  });
}
