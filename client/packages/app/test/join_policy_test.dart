// SPDX-License-Identifier: Apache-2.0
/// Who can join, from the client's side: the Space settings row that changes
/// it, and the sign-up notice that explains an invite-only Space instead of
/// just refusing the account.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/join_policy_row.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

void main() {
  testWidgets('the row shows the current policy and changes it', (
    tester,
  ) async {
    var stored = 'invite';
    final patched = <String>[];

    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        stored = body['join_policy'] as String;
        patched.add(stored);
      }
      return http.Response(
        jsonEncode({'join_policy': stored}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
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
          home: const Scaffold(body: JoinPolicyRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('People with an invite'), findsOneWidget);

    await tester.tap(find.text('Who can join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anyone with the address'));
    await tester.pumpAndSettle();

    // The wire value, not the label: the server only accepts these two.
    expect(patched, ['open']);
  });

  test('an unknown policy from a newer server reads as invite, not open', () {
    expect(api.JoinPolicy.parse('open'), api.JoinPolicy.open);
    expect(api.JoinPolicy.parse('invite'), api.JoinPolicy.invite);
    // The closed one is the only safe default for a value we cannot interpret.
    expect(api.JoinPolicy.parse('approval-queue'), api.JoinPolicy.invite);
  });

  test('a server too old to report the policy says nothing either way', () {
    final version = api.Version.fromJson(const {
      'name': 'slim-m',
      'version': '0.14.1',
      'protocol': 1,
    });
    expect(version.inviteRequired, isNull);
  });
}
