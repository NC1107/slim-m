// SPDX-License-Identifier: Apache-2.0
/// Tests for the sign-in flow's interaction with sync: SyncController is
/// session-driven (see its class doc) and reacts to a fresh sign-in on its
/// own, so nothing on this screen may also start it explicitly, or two
/// competing sockets open and one kicks the other offline.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/sign_in_screen.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: 0,
);

void main() {
  testWidgets(
      'a successful sign-in starts sync exactly once, not twice racing to '
      'open the socket', (tester) async {
    var listChannelsCalls = 0;
    final httpClient = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/auth/login') {
        return http.Response(
          jsonEncode(_tokens.toJson()),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/channels') {
        listChannelsCalls++;
        return http.Response('[]', 200,
            headers: const {'content-type': 'application/json'});
      }
      // Cut sync's start() short right after the channel refresh this test
      // counts: a 404 here is caught by start()'s own try/catch (offline,
      // retry scheduled) well before any real socket is ever attempted.
      if (request.method == 'POST' && request.url.path == '/auth/ws-ticket') {
        return http.Response('{"error":"not found"}', 404);
      }
      return http.Response('{}', 200);
    });

    final container = ProviderContainer(overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: httpClient,
        );
        ref.onDispose(api.close);
        return api;
      }),
      storeProvider.overrideWith((ref) async {
        final db = SlimmDatabase(NativeDatabase.memory());
        ref.onDispose(db.close);
        return MessageStore(db);
      }),
    ]);
    // Disposed explicitly at the end of the test body, not via addTearDown:
    // a failed sync attempt schedules a real retry Timer, and
    // flutter_test's pending-timer check runs before addTearDown callbacks
    // do, so relying on addTearDown here would fail the test on that check
    // rather than on what this test is actually about.

    // Mirrors main(): SyncController is constructed, and its session
    // listener subscribed, before any navigation can reach the sign-in
    // screen - exactly like the real app, and exactly what makes the
    // listener (not an explicit call from this screen) the one thing that
    // starts sync.
    container.read(syncControllerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const SignInScreen(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(1), 'alice');
    await tester.enterText(find.byType(TextField).at(2), 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(listChannelsCalls, 1,
        reason: 'two start() calls each refresh channels once; a single, '
            'session-driven start is the only thing allowed to run');

    container.dispose();
  });
}
