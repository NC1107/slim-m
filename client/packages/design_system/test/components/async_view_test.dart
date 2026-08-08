// SPDX-License-Identifier: Apache-2.0
/// [AppAsyncView]: the three canonical states, and the fourth shape that
/// only shows up once a caller has both a real error and real data at the
/// same time - a refresh that fails after an earlier fetch already
/// succeeded, which Riverpod's own retained-previous-value behaviour makes
/// routine rather than rare.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(
      body: SizedBox(height: 400, width: 300, child: child),
    ),
  ),
);

void main() {
  testWidgets('a bare fetch failure with no prior data shows only the error', (
    tester,
  ) async {
    await _pump(
      tester,
      AppAsyncView<List<int>>(
        value: const AppAsyncState(error: 'boom'),
        data: (context, list) => Text('${list.length} items'),
        errorMessage: 'Could not load the list.',
      ),
    );

    expect(find.text('Could not load the list.'), findsOneWidget);
    expect(find.textContaining('items'), findsNothing);
  });

  testWidgets(
    'a refresh failure that still carries the last known data keeps '
    'showing that data alongside the error, rather than wiping it',
    (tester) async {
      var retried = false;
      await _pump(
        tester,
        AppAsyncView<List<int>>(
          value: AppAsyncState(data: const [1, 2, 3], error: 'boom'),
          data: (context, list) => Text('${list.length} items'),
          errorMessage: 'Could not load the list.',
          onRetry: () => retried = true,
        ),
      );

      expect(find.text('Could not load the list.'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    },
  );

  testWidgets('loading with nothing yet known shows the spinner, not blank', (
    tester,
  ) async {
    await _pump(
      tester,
      AppAsyncView<List<int>>(
        value: const AppAsyncState<List<int>>(),
        data: (context, list) => Text('${list.length} items'),
        errorMessage: 'Could not load the list.',
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Could not load the list.'), findsNothing);
  });

  testWidgets('an empty result is told apart from an error', (tester) async {
    await _pump(
      tester,
      AppAsyncView<List<int>>(
        value: const AppAsyncState(data: <int>[]),
        data: (context, list) => Text('${list.length} items'),
        errorMessage: 'Could not load the list.',
        isEmpty: (list) => list.isEmpty,
        emptyMessage: 'Nothing here yet.',
      ),
    );

    expect(find.text('Nothing here yet.'), findsOneWidget);
    expect(find.text('Could not load the list.'), findsNothing);
    expect(find.text('0 items'), findsNothing);
  });
}
