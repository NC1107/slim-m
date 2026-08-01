// SPDX-License-Identifier: Apache-2.0
/// Tests for the settings avatar section: "Remove" only offers itself when
/// there is something to remove, and removing it round-trips through the
/// real endpoint and clears the preview once `Me` is refetched.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/avatar_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> _meJson(int? avatarUpdatedAt) => {
  'id': 'self',
  'username': 'self',
  'display_name': 'Self',
  'created_at': 0,
  'permissions': 0,
  if (avatarUpdatedAt != null) 'avatar_updated_at': avatarUpdatedAt,
};

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const Scaffold(body: AvatarSettingsSection()),
  ),
);

void main() {
  testWidgets('no avatar set shows only the upload action', (tester) async {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient((request) async {
              if (request.url.path == '/me') {
                return http.Response(
                  jsonEncode(_meJson(null)),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response('', 404);
            }),
          );
          ref.onDispose(api.close);
          return api;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('Browse files'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets(
    'an existing avatar offers Remove, and removing it clears the preview',
    (tester) async {
      int? avatarUpdatedAt = 555;
      final requests = <String>[];
      final container = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: MockClient((request) async {
                requests.add('${request.method} ${request.url.path}');
                if (request.url.path == '/me') {
                  return http.Response(
                    jsonEncode(_meJson(avatarUpdatedAt)),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                if (request.method == 'DELETE' &&
                    request.url.path == '/me/avatar') {
                  avatarUpdatedAt = null;
                  return http.Response('', 204);
                }
                return http.Response('', 404);
              }),
            );
            ref.onDispose(api.close);
            return api;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(requests, contains('DELETE /me/avatar'));
      expect(find.text('Remove'), findsNothing);
    },
  );

  for (final label in ['Photo library', 'Browse files']) {
    testWidgets(
      'tapping $label with no picker result available never calls upload',
      (tester) async {
        final requests = <String>[];
        final container = ProviderContainer(
          overrides: [
            keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
            sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
            apiProvider.overrideWith((ref) {
              final api = SlimmApi(
                baseUrl: Uri.parse('http://localhost:8080'),
                session: ref.watch(sessionProvider),
                httpClient: MockClient((request) async {
                  requests.add('${request.method} ${request.url.path}');
                  if (request.url.path == '/me') {
                    return http.Response(
                      jsonEncode(_meJson(null)),
                      200,
                      headers: {'content-type': 'application/json'},
                    );
                  }
                  return http.Response('', 404);
                }),
              );
              ref.onDispose(api.close);
              return api;
            }),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container));
        await tester.pumpAndSettle();

        /// No platform implementation is registered for file_picker's method
        /// channel in a widget test, so this either throws (caught, shown as
        /// a snack bar) or resolves with no file chosen; either way, the
        /// point under test is that nothing ever reaches the upload endpoint
        /// from a picker that produced nothing to upload.
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(requests, isNot(contains('POST /me/avatar')));
      },
    );
  }
}
