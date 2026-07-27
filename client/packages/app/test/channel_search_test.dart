// SPDX-License-Identifier: Apache-2.0
/// Tests for the channel search panel's loading, error, and empty states: a
/// failed search must say so and offer a retry (unless the failure was a
/// 403, which no retry can fix), and must never render identically to a
/// search that genuinely found nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/channel_search.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('a search in flight shows a spinner, not "no matches"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const ChannelSearchResults(
          results: null,
          knownUsernames: {},
          loading: true,
          failed: false,
          forbidden: false,
          onRetry: _noop,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No matches.'), findsNothing);
  });

  testWidgets('a failed search says so and offers a working retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _harness(
        ChannelSearchResults(
          results: null,
          knownUsernames: const {},
          loading: false,
          failed: true,
          forbidden: false,
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Search failed.'), findsOneWidget);
    expect(
      find.text('No matches.'),
      findsNothing,
      reason: 'a failure must never read as an honest empty result',
    );

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('a 403 explains the denial and offers no retry', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ChannelSearchResults(
          results: null,
          knownUsernames: {},
          loading: false,
          failed: true,
          forbidden: true,
          onRetry: _noop,
        ),
      ),
    );

    expect(
      find.text('You do not have permission to search this channel.'),
      findsOneWidget,
    );
    expect(
      find.text('Retry'),
      findsNothing,
      reason: 'a 403 will not succeed on retry, so none is offered',
    );
  });

  testWidgets('a genuinely empty result reads as "no matches"', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ChannelSearchResults(
          results: [],
          knownUsernames: {},
          loading: false,
          failed: false,
          forbidden: false,
          onRetry: _noop,
        ),
      ),
    );

    expect(find.text('No matches.'), findsOneWidget);
  });
}

void _noop() {}
