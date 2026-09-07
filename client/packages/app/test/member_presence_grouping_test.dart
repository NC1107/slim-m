// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// How the member pane decides who is "online". `isReachablePresence` and
/// `groupMembersByPresence` carry two product rules with no test: hidden is
/// the "appear offline" state and must group as offline, and a member whose
/// presence is unknown counts as offline rather than being assumed online -
/// the only honest default. The two lists are also name-sorted.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_design_system/design_system.dart' show AppPresence;

api.UserProfile _m(String id, String displayName) => api.UserProfile(
  id: id,
  username: id,
  displayName: displayName,
  createdAt: 0,
);

void main() {
  group('isReachablePresence', () {
    test('online, away and dnd count as reachable', () {
      for (final s in [AppPresence.online, AppPresence.away, AppPresence.dnd]) {
        expect(isReachablePresence(s), isTrue, reason: '$s');
      }
    });

    test('offline and hidden do not', () {
      expect(isReachablePresence(AppPresence.offline), isFalse);
      expect(isReachablePresence(AppPresence.hidden), isFalse);
    });
  });

  group('groupMembersByPresence', () {
    test('splits reachable from the rest, hidden and unknown both offline', () {
      final members = [
        _m('a', 'Ana'),
        _m('b', 'Bo'),
        _m('c', 'Cara'),
        _m('d', 'Del'),
      ];
      final grouped = groupMembersByPresence(members, {
        'a': AppPresence.online,
        'b': AppPresence.hidden, // appears offline
        'c': AppPresence.dnd,
        // 'd' is absent: unknown, so offline
      });

      expect(grouped.online.map((m) => m.id), ['a', 'c']);
      expect(grouped.offline.map((m) => m.id), ['b', 'd']);
    });

    test('each group is sorted by display name, case-insensitively', () {
      final members = [_m('b1', 'Banana'), _m('a1', 'apple')];
      final grouped = groupMembersByPresence(members, {
        'b1': AppPresence.online,
        'a1': AppPresence.online,
      });

      expect(grouped.online.map((m) => m.id), [
        'a1',
        'b1',
      ], reason: 'apple sorts before Banana only when case is folded');
    });
  });

  group('rosterEntries', () {
    test('each non-empty group is its counted heading then its members', () {
      final entries = rosterEntries((
        online: [_m('a', 'Ada')],
        offline: [_m('b', 'Bo'), _m('c', 'Cy')],
      ));
      expect(entries, hasLength(5));
      expect((entries[0] as RosterGroupLabel).text, 'Online \u00b7 1');
      expect((entries[1] as RosterMember).profile.id, 'a');
      expect((entries[2] as RosterGroupLabel).text, 'Offline \u00b7 2');
      expect((entries[3] as RosterMember).profile.id, 'b');
      expect((entries[4] as RosterMember).profile.id, 'c');
    });

    test('an empty group contributes no heading', () {
      final entries = rosterEntries((
        online: const [],
        offline: [_m('b', 'Bo')],
      ));
      expect(entries, hasLength(2));
      expect((entries[0] as RosterGroupLabel).text, startsWith('Offline'));
    });
  });
}
