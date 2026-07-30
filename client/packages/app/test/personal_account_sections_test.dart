// SPDX-License-Identifier: Apache-2.0
/// `DevicesSection`'s "Sign out" had no `try` at all: a failure threw out of
/// an async `onPressed` with no catch anywhere above it, so nothing ever
/// reached the user, and there was no test to notice. Now each row owns its
/// own guarded failure.
library;

import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/personal_account_sections.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

String _deviceJson(String id, {bool isCurrent = false}) => jsonEncode({
  'id': id,
  'name': 'A phone',
  'created_at': 0,
  'last_seen_at': 0,
  'is_current': isCurrent,
});

Future<ProviderContainer> _pump(
  WidgetTester tester,
  http.Response Function(http.Request) handler,
) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async => handler(request)),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: DevicesSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('signing out a device removes it from the list', (tester) async {
    var removed = false;
    final container = await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/devices') {
        return http.Response(
          removed ? '[]' : '[${_deviceJson('device-1')}]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') {
        removed = true;
        return http.Response('', 204);
      }
      return http.Response('{}', 404);
    });

    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('No devices signed in.'), findsOneWidget);
    container.dispose();
  });

  /// This is the exact case the finding named: a lost connection while
  /// signing out a device used to throw out of `onPressed` with nothing
  /// above it to catch it, so nothing reached the user at all.
  testWidgets(
    'a failed sign-out shows a safe sentence inline, not a thrown exception',
    (tester) async {
      await _pump(tester, (request) {
        if (request.method == 'GET' && request.url.path == '/devices') {
          return http.Response(
            '[${_deviceJson('device-1')}]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          throw const SocketException('connection refused');
        }
        return http.Response('{}', 404);
      });

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // Still listed, and no exception escaped: `pumpAndSettle` would rethrow one.
      expect(find.text('A phone'), findsOneWidget);
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(
        find.textContaining('the server could not be reached'),
        findsOneWidget,
      );

      // Recovers rather than staying stuck: sign-out can be tried again.
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Sign out'))
            .onPressed,
        isNotNull,
      );
    },
  );
}
