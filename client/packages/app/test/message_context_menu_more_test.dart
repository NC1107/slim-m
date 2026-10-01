// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The message context menu's row cap: Report, Block and the rest sit behind
/// "More" so the first step never passes about eight rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_context_menu.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';

void main() {
  Widget rowWith(MessageActions actions) => harness(
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
    ),
  );

  Offset pressPoint(WidgetTester tester) =>
      tester.getTopLeft(find.byType(MessageContextMenuRegion)) +
      const Offset(30, 30);

  // SlimmApi.report once had no call site; nothing gated that regressing.
  testWidgets('a message not authored by the caller offers Report and Block', (
    tester,
  ) async {
    var reported = false;
    var blocked = false;
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: false,
          onEdit: noop,
          canDelete: false,
          onDelete: noop,
          canManagePins: false,
          pinned: false,
          onTogglePin: noop,
          canReport: true,
          onReport: () => reported = true,
          canBlockAuthor: true,
          onBlockAuthor: () => blocked = true,
          canOpenThread: false,
          onOpenThread: noop,
          canCopyLink: false,
          onCopyLink: noop,
          canForward: false,
          onForward: noop,
          canSave: false,
          onSave: noop,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.text('Report message'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);

    await tester.tap(find.text('Report message'));
    await tester.pumpAndSettle();
    expect(reported, isTrue);

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    expect(blocked, isTrue);
  });

  testWidgets('a fully permitted menu shows at most eight rows, rest in More', (
    tester,
  ) async {
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: true,
          onReply: noop,
          canEdit: true,
          onEdit: noop,
          canDelete: true,
          onDelete: noop,
          canManagePins: true,
          pinned: false,
          onTogglePin: noop,
          canReport: true,
          onReport: noop,
          canBlockAuthor: true,
          onBlockAuthor: noop,
          canOpenThread: true,
          onOpenThread: noop,
          canCopyLink: true,
          onCopyLink: noop,
          canForward: true,
          onForward: noop,
          canSave: true,
          onSave: noop,
          onStartSelecting: noop,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenuItem).evaluate().length, lessThanOrEqualTo(8));
    expect(find.text('More'), findsOneWidget);
    for (final hidden in ['Copy link', 'Forward message', 'Save message']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    for (final shown in ['Copy link', 'Forward message', 'Select messages']) {
      expect(find.text(shown), findsOneWidget, reason: shown);
    }
    expect(find.byType(AppMenuItem).evaluate().length, lessThanOrEqualTo(8));
  });
}
