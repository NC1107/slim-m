// SPDX-License-Identifier: Apache-2.0
/// The grouped continuation gutter's timestamp follows the 12/24-hour
/// preference (#38), not a hardcoded format. Split out of
/// `message_row_test.dart`, which is already at its line budget and whose
/// own scope is grouping, not the exact text a timestamp renders.
///
/// The gutter timestamp is also hover-gated (backlog #119): a grouped row's
/// sent time no longer sits in the left gutter at rest, only while a mouse
/// hovers the row, so every case here hovers first.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/display_preferences.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_app/src/widgets/message_row_identity.dart';

import 'message_row_harness.dart';

Future<void> _pumpGrouped(
  WidgetTester tester,
  TimeFormatPreference preference,
) {
  return tester.pumpWidget(
    harness(
      MessageRow(
        message: message(),
        grouped: true,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onPickReaction: (_) {},
        onReactionTap: (_) {},
        onVote: (_) {},
        actions: noActions,
        editing: false,
        onSubmitEdit: (_) {},
        onCancelEdit: () {},
      ),
      overrides: [
        timeFormatControllerProvider.overrideWith(
          (ref) => TimeFormatController(ref)..state = preference,
        ),
      ],
    ),
  );
}

Future<void> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byType(MessageRow)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('h24 shows the zero-padded 24-hour form on hover', (
    tester,
  ) async {
    await _pumpGrouped(tester, TimeFormatPreference.h24);
    await _hover(tester);

    expect(
      find.text(formatMessageTime(1700000000000, use24Hour: true)),
      findsOneWidget,
    );
  });

  testWidgets('h12 shows the compact 12-hour form instead, on hover', (
    tester,
  ) async {
    await _pumpGrouped(tester, TimeFormatPreference.h12);
    await _hover(tester);

    expect(
      find.text(formatMessageTime(1700000000000, use24Hour: false)),
      findsOneWidget,
    );
    expect(
      find.text(formatMessageTime(1700000000000, use24Hour: true)),
      findsNothing,
    );
  });
}
