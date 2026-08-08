// SPDX-License-Identifier: Apache-2.0
/// The "N replies" affordance a message row shows once it has an opened
/// thread: `ThreadReplySummary` (`widgets/message_row_parts.dart`), wired
/// into `MessageRow` from `MessageExtras.threadReplyCount` and
/// `threadLastReplyAt`.
///
/// Split out of `message_row_test.dart` rather than added to it: that file
/// is already allowlisted at the 300/500-line budget's hard ceiling for its
/// own scope (the row plus its context menu), and this is a self-contained
/// slice with its own fixtures.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_context_menu.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_app/src/widgets/message_row_identity.dart';
import 'package:slimm_app/src/widgets/message_row_parts.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';

Widget _rowWith({
  int? threadReplyCount,
  int? threadLastReplyAt,
  MessageActions actions = noActions,
}) => harness(
  MessageRow(
    message: message(),
    grouped: false,
    showNewDivider: false,
    knownUsernames: const {},
    onRetry: () {},
    onDiscard: () {},
    onPickReaction: (_) {},
    onReactionTap: (_) {},
    onVote: (_) {},
    actions: actions,
    editing: false,
    onSubmitEdit: (_) {},
    onCancelEdit: () {},
    threadReplyCount: threadReplyCount,
    threadLastReplyAt: threadLastReplyAt,
  ),
);

void main() {
  testWidgets('a message with no thread shows no reply affordance at all', (
    tester,
  ) async {
    await tester.pumpWidget(_rowWith());
    expect(find.byType(ThreadReplySummary), findsNothing);
  });

  testWidgets('an opened thread with zero replies shows no affordance either - '
      'never an empty "0 replies"', (tester) async {
    await tester.pumpWidget(_rowWith(threadReplyCount: 0));
    expect(find.byType(ThreadReplySummary), findsNothing);
    expect(find.textContaining('0 repl'), findsNothing);
  });

  testWidgets('a single reply reads "1 reply", singular', (tester) async {
    await tester.pumpWidget(_rowWith(threadReplyCount: 1));
    expect(find.text('1 reply'), findsOneWidget);
  });

  testWidgets('several replies read "N replies", plural', (tester) async {
    await tester.pumpWidget(_rowWith(threadReplyCount: 3));
    expect(find.text('3 replies'), findsOneWidget);
  });

  testWidgets(
    'a known last-reply time is appended, formatted the same way a day '
    'divider would',
    (tester) async {
      const lastReplyAt = 1700000000000;
      await tester.pumpWidget(
        _rowWith(threadReplyCount: 3, threadLastReplyAt: lastReplyAt),
      );
      expect(
        find.text('3 replies · Last reply ${formatMessageDay(lastReplyAt)}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping the affordance opens the thread when the caller allows it',
    (tester) async {
      var opened = false;
      final actions = MessageActions(
        canReply: true,
        onReply: noop,
        canEdit: false,
        onEdit: noop,
        canDelete: false,
        onDelete: noop,
        canManagePins: false,
        pinned: false,
        onTogglePin: noop,
        canReport: false,
        onReport: noop,
        canBlockAuthor: false,
        onBlockAuthor: noop,
        canOpenThread: true,
        onOpenThread: () => opened = true,
      );
      await tester.pumpWidget(_rowWith(threadReplyCount: 2, actions: actions));

      await tester.tap(find.byType(ThreadReplySummary));
      expect(opened, isTrue);
    },
  );

  testWidgets('a count plus an absolute last-reply date does not overflow a '
      'phone-width row', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: SizedBox(
              width: 342,
              // A date months in the past renders the long absolute form, not "Today"/"Yesterday".
              child: ThreadReplySummary(
                replyCount: 3,
                lastReplyAt: 1700000000000,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the affordance is inert, with no tap handler, when the caller cannot '
    'open the thread - a view-only member sees the count but cannot act on '
    'it, the same "disabled means no handler at all" treatment '
    'AppSegmentedOption gives an unavailable choice',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_rowWith(threadReplyCount: 2));

      expect(find.byType(InkWell), findsNothing);
      final node = tester.getSemantics(find.byType(ThreadReplySummary));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    },
  );
}
