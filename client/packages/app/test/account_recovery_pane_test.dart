// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Space settings route to a reset code.
///
/// Issuing already worked, from a member's profile popover. Nothing in Space
/// settings mentioned recovery, so an administrator looking where admin
/// actions live found nothing and read that as the feature being absent. What
/// these hold is that the second route exists, that it reaches the same sheet,
/// and that it needs ADMINISTRATOR the way the server route does.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/account_recovery_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin-1',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: 0,
);

/// Two members, so picking one is a real choice rather than the only row.
String _membersJson() => jsonEncode([
  {
    'id': 'user-9',
    'username': 'ada',
    'display_name': 'Ada',
    'created_at': 0,
    'permissions': 0,
  },
  {
    'id': 'user-4',
    'username': 'grace',
    'display_name': 'Grace',
    'created_at': 0,
    'permissions': 0,
  },
]);

Future<void> _pump(WidgetTester tester, {required int permissions}) async {
  final client = MockClient((request) async {
    if (request.url.path == '/members') {
      return http.Response(
        _membersJson(),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{}',
      404,
      headers: {'content-type': 'application/json'},
    );
  });

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      myPermissionsProvider.overrideWithValue(permissions),
      apiProvider.overrideWith((ref) {
        final built = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: client,
        );
        ref.onDispose(built.close);
        return built;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(
          body: SingleChildScrollView(child: AccountRecoveryPane()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an administrator reaches the issuing sheet without ever opening '
      'a member popover', (tester) async {
    await _pump(tester, permissions: Perm.administrator);

    // The pane explains recovery, because there is no email path to guess at.
    expect(find.textContaining('no recovery email'), findsOneWidget);

    await tester.tap(find.text('Issue a reset code'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a member'),
      findsOneWidget,
      reason: 'the action picks who it is for rather than asking for an id',
    );

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();

    // The existing sheet, named for the member the picker returned.
    expect(
      find.textContaining('Ada'),
      findsWidgets,
      reason: 'the picked member has to reach showResetCodeSheet',
    );
  });

  testWidgets('a cancelled pick issues nothing', (tester) async {
    await _pump(tester, permissions: Perm.administrator);

    await tester.tap(find.text('Issue a reset code'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a member'), findsOneWidget);

    Navigator.of(tester.element(find.text('Choose a member'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Choose a member'), findsNothing);
    expect(
      find.text('Issue a reset code'),
      findsOneWidget,
      reason: 'backing out returns to the pane, having issued nothing',
    );
  });

  testWidgets('without ADMINISTRATOR the row is inert and says why', (
    tester,
  ) async {
    await _pump(tester, permissions: Perm.manageServer);

    expect(find.text('Administrators only'), findsOneWidget);
    await tester.tap(find.text('Issue a reset code'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a member'),
      findsNothing,
      reason: 'the server refuses anything less, so the client must not ask',
    );
  });
}
