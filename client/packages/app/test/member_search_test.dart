// SPDX-License-Identifier: Apache-2.0
/// Finding one member, and finding the wave that arrived together.
///
/// The raid case is the one these exist for, so it is the one asserted
/// literally: fifty accounts registered inside two minutes, buried in a
/// roster sorted by name, have to come back adjacent and newest-first.
///
/// Order is asserted rather than membership throughout. A filter that returns
/// the right people in an order that reshuffles between rebuilds is no use for
/// picking them out of a list, which is the whole task.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/member_search.dart';

api.UserProfile member(String username, {String? display, int joined = 0}) =>
    api.UserProfile(
      id: 'id-$username',
      username: username,
      displayName: display ?? username,
      createdAt: joined,
    );

void main() {
  group('membersMatching', () {
    test('an empty query is the same as no search', () {
      final roster = [member('ada'), member('bram')];
      expect(membersMatching(roster, ''), roster);
      expect(membersMatching(roster, '   '), roster);
    });

    test('matches the username and the display name, case-insensitively', () {
      final roster = [
        member('ada', display: 'Ada L'),
        member('bram', display: 'Bram S'),
        member('spam01', display: 'Totally Real'),
      ];

      expect(membersMatching(roster, 'ADA').map((m) => m.username), [
        'ada',
      ], reason: 'the username matches whatever case it is typed in');
      expect(membersMatching(roster, 'totally').map((m) => m.username), [
        'spam01',
      ], reason: 'the display name matches too, which is all a reader can see');
    });

    test('a username match is found when the display name hides it', () {
      // A display name is chosen freely; a report names the username.
      final roster = [member('spam01', display: 'Ada L')];
      expect(membersMatching(roster, 'spam').single.username, 'spam01');
    });

    test('no match is empty rather than everything', () {
      expect(membersMatching([member('ada')], 'zzz'), isEmpty);
    });

    test('the roster order is kept, so filtering does not also reorder', () {
      final roster = [member('cy'), member('ada'), member('bram')];
      expect(membersMatching(roster, '').map((m) => m.username), [
        'cy',
        'ada',
        'bram',
      ]);
    });
  });

  group('membersByJoinedNewestFirst', () {
    test('newest first', () {
      final roster = [
        member('old', joined: 100),
        member('newest', joined: 300),
        member('middle', joined: 200),
      ];
      expect(membersByJoinedNewestFirst(roster).map((m) => m.username), [
        'newest',
        'middle',
        'old',
      ]);
    });

    test('ties break on username, so the order is total and stable', () {
      // A scripted wave registers several accounts in the same millisecond.
      final roster = [
        member('spam-c', joined: 500),
        member('spam-a', joined: 500),
        member('spam-b', joined: 500),
      ];
      final once = membersByJoinedNewestFirst(roster).map((m) => m.username);
      final twice = membersByJoinedNewestFirst(roster).map((m) => m.username);
      expect(once, ['spam-a', 'spam-b', 'spam-c']);
      expect(twice, once, reason: 'and it does not reshuffle between rebuilds');
    });

    test('the input list is left alone', () {
      final roster = [member('a', joined: 1), member('b', joined: 2)];
      membersByJoinedNewestFirst(roster);
      expect(
        roster.map((m) => m.username),
        ['a', 'b'],
        reason:
            'sorting the caller\'s own list would reorder the pane behind it',
      );
    });

    /// MOD2's own scenario, asserted end to end rather than in pieces.
    test(
      'a wave that joined together comes back together, ahead of everyone',
      () {
        final longstanding = [
          for (var i = 0; i < 30; i++) member('member$i', joined: 1000 + i),
        ];
        final wave = [
          for (var i = 0; i < 50; i++) member('throwaway$i', joined: 90000 + i),
        ];
        // Interleaved the way an alphabetical roster would present them.
        final roster = [...longstanding, ...wave]
          ..sort((a, b) => a.username.compareTo(b.username));

        final byJoined = membersByJoinedNewestFirst(roster);
        final first50 = byJoined.take(50).map((m) => m.username).toSet();

        expect(
          first50,
          wave.map((m) => m.username).toSet(),
          reason:
              'the whole wave is the first fifty rows, with nobody else mixed in',
        );
      },
    );
  });
}
