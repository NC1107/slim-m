// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The activity field on presence: read from a frame and a batch lookup, and
/// written back in the shape the server accepts.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('presence.changed carries an activity when the server sends one', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'presence.changed',
        'user_id': 'u1',
        'status': 'online',
        'activity': {
          'type': 'listening',
          'title': 'Song',
          'subtitle': 'Artist',
          'started_at': 1700000000000,
        },
      }),
    );
    final activity = (event as PresenceChanged).activity!;
    expect(activity.kind, ActivityKind.listening);
    expect(activity.title, 'Song');
    expect(activity.subtitle, 'Artist');
    expect(activity.startedAt, 1700000000000);
  });

  test('a frame without one, or with an unknown kind, has no activity', () {
    for (final extra in <Map<String, Object?>>[
      {},
      {
        'activity': {'type': 'dancing', 'title': 'x'},
      },
      {
        'activity': {'type': 'playing', 'title': ''},
      },
    ]) {
      final event = ServerEvent.parse(
        jsonEncode({
          'type': 'presence.changed',
          'user_id': 'u1',
          'status': 'online',
          ...extra,
        }),
      );
      expect((event as PresenceChanged).activity, isNull);
    }
  });

  test('a batch lookup entry reads its activity', () {
    final status = PresenceStatus.fromJson({
      'user_id': 'u1',
      'status': 'away',
      'activity': {'type': 'playing', 'title': 'Game'},
    });
    expect(status.activity?.kind, ActivityKind.playing);
    expect(status.activity?.subtitle, isNull);
  });

  test('toJson omits what is unknown, matching the server schema', () {
    const activity = PresenceActivity(
      kind: ActivityKind.listening,
      title: 'Song',
    );
    expect(activity.toJson(), {'type': 'listening', 'title': 'Song'});
  });
}
