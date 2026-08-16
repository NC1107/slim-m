// SPDX-License-Identifier: Apache-2.0
/// The member pane's search box and sort toggle, driven through the real
/// widget rather than through the functions behind them.
///
/// `member_search_test.dart` already proves the filtering and ordering. What
/// is left to prove, and what only a pumped tree can answer, is that the pane
/// actually uses them: that typing reaches the list, that the toggle changes
/// which rows appear and in what order, and that the roster count does not
/// quietly follow the filter.
///
/// A separate file from `member_pane_test.dart`, which is already past the
/// review budget at 438 lines.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/member_pane.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

UserProfile _profile(String id, String name, {int joined = 0}) => UserProfile(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  createdAt: joined,
);

SlimmApi _fakeApi(SessionStore session) => SlimmApi(
  baseUrl: Uri.parse('http://localhost:8080'),
  session: session,
  httpClient: MockClient((request) async {
    if (request.url.path == '/me') {
      return http.Response(
        jsonEncode({
          'id': 'self',
          'username': 'self',
          'display_name': 'Self',
          'created_at': 0,
        }),
        200,
      );
    }
    if (request.url.path == '/presence') {
      return http.Response(jsonEncode(const []), 200);
    }
    throw StateError('unexpected request in this test: ${request.url}');
  }),
);

List<Override> _overrides(List<UserProfile> members) => [
  keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
  sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
  apiProvider.overrideWith((ref) {
    final api = _fakeApi(ref.watch(sessionProvider));
    ref.onDispose(api.close);
    return api;
  }),
  membersProvider.overrideWith((ref) async => members),
];

/// A roster with a wave of throwaways buried in it, which is MOD2's own case.
List<UserProfile> _roster() => [
  _profile('1', 'Ada', joined: 1000),
  _profile('2', 'Bram', joined: 1100),
  _profile('3', 'spam01', joined: 90000),
  _profile('4', 'spam02', joined: 90001),
  _profile('5', 'Zed', joined: 1200),
];

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: AppMemberPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing filters the rows the pane shows', (tester) async {
    final container = ProviderContainer(overrides: _overrides(_roster()));
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('spam01'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'spam');
    await tester.pumpAndSettle();

    expect(find.text('spam01'), findsOneWidget);
    expect(find.text('spam02'), findsOneWidget);
    expect(
      find.text('Ada'),
      findsNothing,
      reason: 'a filtered pane must actually drop the rows that do not match',
    );
  });

  testWidgets('the roster count stays the whole Space while filtering', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: _overrides(_roster()));
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.textContaining('MEMBERS · 5'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'spam');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('MEMBERS · 5'),
      findsOneWidget,
      reason:
          'this header answers how big the Space is, not how big the filter is',
    );
  });

  testWidgets('a search that matches nobody says so', (tester) async {
    final container = ProviderContainer(overrides: _overrides(_roster()));
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.enterText(find.byType(TextField), 'nobody-by-that-name');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Nobody matches'),
      findsOneWidget,
      reason: 'an empty pane must read as an answer, not as a failed load',
    );
  });

  testWidgets('the sort toggle groups the recent joiners together', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: _overrides(_roster()));
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(
      find.textContaining('RECENTLY JOINED'),
      findsNothing,
      reason: 'presence grouping is still the default',
    );

    await tester.tap(find.bySemanticsLabel('Sort by most recently joined'));
    await tester.pumpAndSettle();

    expect(find.textContaining('RECENTLY JOINED · 5'), findsOneWidget);
    expect(
      find.textContaining('OFFLINE'),
      findsNothing,
      reason:
          'sorting by arrival replaces the presence grouping rather than '
          'nesting inside it, or the wave is split across two groups again',
    );

    // The two throwaways are the first rows, which is the whole point.
    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.startsWith('spam') || t == 'Ada' || t == 'Zed')
        .toList();
    expect(rows.take(2), [
      'spam02',
      'spam01',
    ], reason: 'newest first, so the wave sits at the top together');
  });

  testWidgets('search and sort compose', (tester) async {
    final container = ProviderContainer(overrides: _overrides(_roster()));
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.bySemanticsLabel('Sort by most recently joined'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'spam');
    await tester.pumpAndSettle();

    expect(find.textContaining('RECENTLY JOINED · 2'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
  });
}
