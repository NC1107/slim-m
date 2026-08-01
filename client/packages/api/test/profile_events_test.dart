// SPDX-License-Identifier: Apache-2.0
/// Frame-parsing coverage for `ProfileChanged`, the event that closes the
/// recorded debt that a display name change never reached a live client.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('profile.changed decodes to ProfileChanged carrying only the id', () {
    final event = ServerEvent.parse(jsonEncode({
      'type': 'profile.changed',
      'user_id': 'u',
    }));
    expect(event, isA<ProfileChanged>());
    expect((event! as ProfileChanged).userId, 'u');
  });

  test('a profile.changed frame missing user_id is ignored, not a crash', () {
    expect(
      ServerEvent.parse(jsonEncode({'type': 'profile.changed'})),
      isNull,
    );
  });
}
