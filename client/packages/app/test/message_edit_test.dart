// SPDX-License-Identifier: Apache-2.0
/// Tests for the message row's inline edit: the body swaps for a pre-filled
/// [MessageEditField], and saving and cancelling each report exactly once.
///
/// Split out of `message_row_test.dart` on the widget seam, the same way the
/// context menu suite was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_edit_field.dart';
import 'package:slimm_app/src/widgets/message_row.dart';

import 'message_row_harness.dart';

void main() {
  testWidgets('editing swaps the body for a pre-filled field', (tester) async {
    await tester.pumpWidget(
      harness(
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
          actions: noActions,
          editing: true,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );

    expect(find.byType(MessageEditField), findsOneWidget);
    expect(find.widgetWithText(TextField, 'hello there'), findsOneWidget);
  });

  testWidgets('saving reports the edited text', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      harness(
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
          actions: noActions,
          editing: true,
          onSubmitEdit: (text) => submitted = text,
          onCancelEdit: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'edited content');
    await tester.tap(find.text('Save'));

    expect(submitted, 'edited content');
  });

  testWidgets('cancel leaves the row rendered as unedited', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      harness(
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
          actions: noActions,
          editing: true,
          onSubmitEdit: (_) {},
          onCancelEdit: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });
}
