// SPDX-License-Identifier: Apache-2.0
/// Poll cleanup: the voted option used to be told from the others by colour
/// alone, a closed poll said so only in fine caption text nobody reads first,
/// and each option's percentage started at a different horizontal offset
/// depending on how many digits it had.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/poll_view.dart';
import 'package:slimm_design_system/design_system.dart';

api.Poll _poll({
  int? votedOption,
  bool closed = false,
  List<int> votes = const [1, 3],
}) => api.Poll(
  question: 'Favourite colour?',
  options: [
    for (var i = 0; i < votes.length; i++)
      api.PollOption(position: i, label: 'Option $i', votes: votes[i]),
  ],
  totalVotes: votes.fold(0, (a, b) => a + b),
  votedOption: votedOption,
  closeAt: null,
  closed: closed,
);

Widget _app(api.Poll poll) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(
    body: PollView(poll: poll, onVote: (_) {}),
  ),
);

void main() {
  testWidgets('the voted option carries a check, not colour alone', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_poll(votedOption: 1)));

    expect(find.byIcon(AppIcons.check), findsOneWidget);
  });

  testWidgets('an option nobody has voted for shows no check', (tester) async {
    await tester.pumpWidget(_app(_poll()));

    expect(find.byIcon(AppIcons.check), findsNothing);
  });

  testWidgets('a closed poll carries a glanceable tag beside the question', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_poll(closed: true)));

    expect(find.text('CLOSED'), findsOneWidget);
  });

  testWidgets('an open poll carries no closed tag', (tester) async {
    await tester.pumpWidget(_app(_poll(closed: false)));

    expect(find.text('CLOSED'), findsNothing);
  });

  testWidgets(
    "every option's percentage lines up in a column, whatever its digit "
    'count',
    (tester) async {
      // 1 of 100 votes (1%) beside 99 of 100 (99%): one digit against two.
      await tester.pumpWidget(_app(_poll(votes: const [1, 99])));

      final oneDigit = find.ancestor(
        of: find.text('1%'),
        matching: find.byType(SizedBox),
      );
      final twoDigit = find.ancestor(
        of: find.text('99%'),
        matching: find.byType(SizedBox),
      );
      expect(
        tester.getSize(oneDigit.first).width,
        tester.getSize(twoDigit.first).width,
        reason:
            'a fixed-width percentage column is what keeps every option\'s '
            'bar and label the same shape regardless of the number inside it',
      );
    },
  );
}
