// SPDX-License-Identifier: Apache-2.0
/// History was capped and the transcript said so was the beginning.
///
/// `/sync` and the channel screen's own hydration both stop at 50 messages
/// and the local store hands over the newest 200 rows, so any busier channel
/// had history nothing could reach. On top of that the transcript rendered
/// `ChannelStartHeader` from the channel's name alone: it announced the start
/// of the conversation while sitting directly above the messages it had not
/// loaded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_transcript_widgets.dart';
import 'package:slimm_data/data.dart';

import 'channel_history_harness.dart';

/// Unmounting deliberately, with a few more pumps, rather than leaving it to
/// flutter_test's teardown; see `channel_screen_test.dart` for why drift's
/// deferred stream cleanup needs this.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<Set<String>> _storedIds(SlimmDatabase db) async =>
    (await db.select(db.messages).get()).map((m) => m.id).toSet();

List<int> _range(int from, int to) => [
  for (var seq = from; seq <= to; seq++) seq,
];

void main() {
  testWidgets(
    'the start of the channel is not announced above history that exists',
    (tester) async {
      final harness = await mountChannel(
        tester,
        serverSeqs: _range(1, 200),
        seededSeqs: _range(151, 200),
        holdOlderPages: true,
      );

      expect(find.byType(ChannelStartHeader), findsNothing);

      await scrollToOldest(tester);

      expect(
        find.byType(ChannelStartHeader),
        findsNothing,
        reason:
            'the oldest loaded row is not known to be the channel first, so '
            'nothing may claim the conversation begins above it',
      );
      expect(find.byType(HistoryTopAffordance), findsOneWidget);

      harness.releaseOlderPages();
      await flush(tester);

      expect(
        find.byType(ChannelStartHeader),
        findsNothing,
        reason: 'a full page came back, so there is still more above it',
      );

      await _unmount(tester);
    },
  );

  testWidgets(
    'the start of the channel is announced once the oldest loaded row is '
    'genuinely its first',
    (tester) async {
      await mountChannel(
        tester,
        serverSeqs: _range(1, 80),
        seededSeqs: _range(41, 80),
      );

      // Twice: the first reaches the top and pages, which grows the list out from under the reader.
      await scrollToOldest(tester);
      await scrollToOldest(tester);

      expect(
        find.byType(ChannelStartHeader),
        findsOneWidget,
        reason:
            'the server answered with fewer than a page, which is the only '
            'evidence that nothing older exists',
      );
      expect(find.byType(HistoryTopAffordance), findsNothing);
      expect(
        find.text('message 1'),
        findsOneWidget,
        reason:
            'the page that proved where the channel starts has to be on '
            'screen under the header, not merely counted',
      );

      await _unmount(tester);
    },
  );

  testWidgets('scrolling to the top loads and prepends an older page', (
    tester,
  ) async {
    final harness = await mountChannel(
      tester,
      serverSeqs: _range(1, 200),
      seededSeqs: _range(151, 200),
    );

    expect(await _storedIds(harness.db), isNot(contains('m150')));

    await scrollToOldest(tester);

    expect(
      harness.historyRequests.map((u) => u.queryParameters['before']),
      contains('151'),
      reason: 'the page must be keyed on the oldest seq already held',
    );
    expect(
      await _storedIds(harness.db),
      contains('m150'),
      reason: 'an older page has to land in the local store, not just be read',
    );

    await _unmount(tester);
  });

  testWidgets('paged history past the store window still reaches the '
      'transcript', (tester) async {
    await mountChannel(
      tester,
      serverSeqs: _range(1, 350),
      seededSeqs: _range(151, 350),
    );

    final before = transcriptItemCount(tester);
    await scrollToOldest(tester);

    expect(
      transcriptItemCount(tester),
      greaterThan(before),
      reason:
          'the local store hands over a fixed newest-N window, so a page '
          'below it is written and then invisible unless the window grows',
    );

    await _unmount(tester);
  });

  testWidgets('a refused page says so and is not retried on its own', (
    tester,
  ) async {
    final harness = await mountChannel(
      tester,
      serverSeqs: _range(1, 200),
      seededSeqs: _range(151, 200),
      olderPagesFail: true,
    );

    await scrollToOldest(tester);
    final afterFailure = harness.historyRequests.length;

    expect(find.text('Could not load earlier messages.'), findsOneWidget);
    await flush(tester);
    expect(
      harness.historyRequests.length,
      afterFailure,
      reason:
          'the top of the list is still in view, so retrying on its own '
          'would hammer whatever just refused',
    );

    await tester.tap(find.text('Retry'));
    await flush(tester);

    expect(
      harness.historyRequests.length,
      greaterThan(afterFailure),
      reason: 'the retry is the way back, so it has to actually ask again',
    );

    await _unmount(tester);
  });

  testWidgets('a channel with nothing older than the loaded rows is not paged '
      'again once its start is known', (tester) async {
    final harness = await mountChannel(
      tester,
      serverSeqs: _range(1, 80),
      seededSeqs: _range(41, 80),
    );

    await scrollToOldest(tester);
    final afterFirst = harness.historyRequests.length;

    // Back to the newest and up again, which is what a reader does; standing still at the top fires nothing.
    final scroll = transcriptScroll(tester);
    scroll.jumpTo(scroll.position.minScrollExtent);
    await flush(tester);
    await scrollToOldest(tester);

    expect(
      harness.historyRequests.length,
      afterFirst,
      reason:
          'the top of the list stays in view, so a reached start that kept '
          'asking would be an unbounded request loop',
    );

    await _unmount(tester);
  });
}
