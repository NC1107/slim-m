// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// AppErrorState's persistence contract, and the one narrow exception to it.
///
/// A failure is a state, not an event: it stays until something changes it.
/// autoDismissAfter is the deliberate carve-out for a low-stakes,
/// self-correcting action failure (a gif that would not attach), added
/// 2026-09-03 so such an error clears itself instead of sticking forever -
/// without becoming a SnackBar, which the error grammar and check-error-surface
/// both forbid.
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
}
