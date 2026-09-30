// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// AppErrorState's persistence contract, and the one narrow exception to it.
///
/// A failure is a state, not an event: it stays until something changes it.
/// autoDismissAfter is the deliberate carve-out for a low-stakes,
/// self-correcting action failure (a gif that would not attach), added
/// 2026-09-03 so such an error clears itself instead of sticking forever -
/// without becoming a SnackBar, which the error grammar and check-error-surface
/// both forbid.
///
/// Also its height: every caller hands this loose vertical constraints, and the
/// Column's default MainAxisSize.max stretched one line of text into a border
/// the full height of the pane. The channel rail shipped roughly 1,200 physical
/// pixels of empty bordered sidebar that way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('without autoDismissAfter it stays until dismissed', (
    tester,
  ) async {
    var dismissed = false;
    await _pump(
      tester,
      AppErrorState(message: 'Nope', onDismiss: () => dismissed = true),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(dismissed, isFalse, reason: 'a failure is a state, not an event');
    expect(find.text('Nope'), findsOneWidget);
  });

  testWidgets('autoDismissAfter fires onDismiss on its own', (tester) async {
    var dismissed = false;
    await _pump(
      tester,
      AppErrorState(
        message: 'Could not attach that gif.',
        onDismiss: () => dismissed = true,
        autoDismissAfter: const Duration(seconds: 6),
      ),
    );
    expect(dismissed, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(dismissed, isFalse, reason: 'not yet');
    await tester.pump(const Duration(seconds: 4));
    expect(dismissed, isTrue, reason: 'cleared itself past the delay');
  });

  testWidgets('autoDismissAfter without onDismiss never throws', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppErrorState(
        message: 'orphan',
        autoDismissAfter: Duration(seconds: 1),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('orphan'), findsOneWidget);
  });

  testWidgets(
      'it is as tall as its own content, not as tall as the space '
      'it is offered', (tester) async {
    const offered = 560.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(
          body: SizedBox(
            width: 248,
            height: offered,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: AppErrorState(message: 'Could not load channels.'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(AppErrorState));
    final text = tester.getRect(find.text('Could not load channels.'));
    expect(
      box.height,
      lessThan(offered / 2),
      reason:
          'a one-line failure must not enclose the pane it sits in; this is '
          'the 1,200px bordered sidebar the rail shipped',
    );
    expect(
      box.height,
      lessThanOrEqualTo(text.height + AppSpacing.s12 * 2 + 2),
      reason: 'the border hugs the line plus its own padding, nothing more',
    );
    expect(
      box.width,
      248,
      reason: 'width still fills, so the box lines up with the rows above it',
    );
  });
}
