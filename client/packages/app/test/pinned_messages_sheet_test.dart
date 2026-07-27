// SPDX-License-Identifier: Apache-2.0
/// Tests for the pinned messages sheet's empty, loading, and error states:
/// a failed first load must say so and offer a retry, never spin forever or
/// read as an honest "nothing pinned".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/pinned_messages_sheet.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Future<void> _pump(
    WidgetTester tester, ProviderContainer container, String channelId) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPinnedMessagesSheet(context, channelId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a failed first load says so and offers a retry that recovers it',
      (tester) async {
    var fail = true;
    final container = ProviderContainer(overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (fail) return http.Response('server error', 500);
            return http.Response('[]', 200,
                headers: {'content-type': 'application/json'});
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, 'c1');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load pinned messages.'), findsOneWidget);
    expect(find.text('Nothing pinned yet.'), findsNothing,
        reason: 'a failed load must never read as an honest empty state');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a failure must not spin forever');

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing pinned yet.'), findsOneWidget);
    expect(find.text('Could not load pinned messages.'), findsNothing);
  });

  testWidgets('a 403 explains the denial and offers no retry', (tester) async {
    final container = ProviderContainer(overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            return http.Response('forbidden', 403);
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, 'c1');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('You do not have permission to see pins here.'),
        findsOneWidget);
    expect(find.text('Retry'), findsNothing,
        reason: 'a 403 will not succeed on retry, so none is offered');
  });
}
