// SPDX-License-Identifier: Apache-2.0
/// The compact quote itself: what it shows when the parent resolved, and -
/// the property that matters - what it refuses to show when it did not.
///
/// `reply_quote_honesty_test.dart` drives the same widget through a real
/// channel screen, for the blocked-author and deleted-parent cases
/// specifically; this file is the plain rendering contract underneath both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/reply_quote.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';

void main() {
  testWidgets('a resolved parent shows its author and a snippet', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyQuote(
          resolved: message(
            id: 'parent',
            authorId: 'priya',
            authorDisplayName: 'Priya',
            content: 'the original text',
          ),
          onTap: () {},
        ),
      ),
    );

    // One merged Text.rich now, not two Text widgets - see reply_quote.dart.
    expect(find.textContaining('Priya'), findsOneWidget);
    expect(find.textContaining('the original text'), findsOneWidget);
    expect(find.text('Message unavailable'), findsNothing);
  });

  testWidgets('an unresolved parent names neither an author nor any content', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const ReplyQuote(resolved: null, onTap: _noop)),
    );

    expect(find.text('Message unavailable'), findsOneWidget);
    // Nothing from a real message can appear: there is no message to draw it from.
    expect(find.text('Priya'), findsNothing);
  });

  testWidgets('a long parent is cut to one line, not spilled in full', (
    tester,
  ) async {
    final long = List.filled(200, 'word').join(' ');
    await tester.pumpWidget(
      harness(
        ReplyQuote(
          resolved: message(id: 'parent', content: long),
          onTap: () {},
        ),
      ),
    );

    expect(find.text(long), findsNothing, reason: 'a quote is compact');
  });

  testWidgets(
    'a long real display name does not overflow a phone-width column',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: Scaffold(
              body: SizedBox(
                width: 342,
                child: ReplyQuote(
                  resolved: message(
                    id: 'parent',
                    authorDisplayName:
                        'Christoph Bartholomew Fitzgerald-Huang III',
                    content: 'short reply',
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tapping the quote calls onTap, resolved or not', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      harness(ReplyQuote(resolved: null, onTap: () => tapped++)),
    );
    await tester.tap(find.byType(ReplyQuote));
    expect(
      tapped,
      1,
      reason: 'a jump can still succeed further back in history',
    );
  });
}

void _noop() {}
