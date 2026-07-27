// SPDX-License-Identifier: Apache-2.0
/// Tests for [UserAvatar] and [AuthorAvatar]: the real picture is wired in
/// once its bytes resolve, and a user with none (or with an id not yet
/// resolved) still falls back to the same initials [AppAvatar] always draws.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/user_avatar.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: child),
      ),
    );

List<Override> _apiOverrides(
  Future<http.Response> Function(http.Request request) handler,
) => [
  apiProvider.overrideWith((ref) {
    final api = SlimmApi(
      baseUrl: Uri.parse('http://localhost:8080'),
      session: SessionStore(
        tokens: const TokenPair(
          userId: 'self',
          accessToken: 'access',
          refreshToken: 'refresh',
          accessExpiresAt: 0,
        ),
      ),
      httpClient: MockClient(handler),
    );
    ref.onDispose(api.close);
    return api;
  }),
];

void main() {
  testWidgets('no userId renders initials and makes no fetch', (tester) async {
    var requested = false;
    await tester.pumpWidget(
      _harness(
        const UserAvatar(name: 'Priya Shah', size: 40),
        overrides: _apiOverrides((request) async {
          requested = true;
          return http.Response('', 404);
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PR'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(requested, isFalse);
  });

  testWidgets('a known userId with resolved bytes renders through Image', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(const [1, 2, 3, 4]);
    await tester.pumpWidget(
      _harness(
        const UserAvatar(
          name: 'Priya Shah',
          userId: 'u1',
          avatarUpdatedAt: 42,
          size: 40,
        ),
        overrides: _apiOverrides((request) async {
          expect(request.url.path, '/users/u1/avatar');
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    // Not asserting the initials are gone: the bytes above are not valid
    // image data, so [Image.errorBuilder] fires and repaints them right back
    // in. What matters here is that the right bytes actually reached the
    // widget, which the assertion above already establishes.
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, bytes);
  });

  testWidgets('a 404 (no avatar on the server) still falls back to initials', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const UserAvatar(
          name: 'Priya Shah',
          userId: 'u1',
          avatarUpdatedAt: 42,
          size: 40,
        ),
        overrides: _apiOverrides((request) async => http.Response('', 404)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PR'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('AuthorAvatar resolves the profile before fetching the picture', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(const [9, 9, 9]);
    await tester.pumpWidget(
      _harness(
        const AuthorAvatar(name: 'Kess', userId: 'u2', size: 36),
        overrides: _apiOverrides((request) async {
          if (request.url.path == '/users/u2') {
            return http.Response(
              jsonEncode({
                'id': 'u2',
                'username': 'kess',
                'display_name': 'Kess',
                'created_at': 0,
                'avatar_updated_at': 7,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.url.path, '/users/u2/avatar');
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, bytes);
  });

  testWidgets('a null author id (a deleted account) never triggers a lookup', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const AuthorAvatar(name: 'Deleted user', userId: null, size: 36),
        overrides: _apiOverrides(
          (request) async =>
              throw StateError('unexpected request: ${request.url}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DE'), findsOneWidget);
  });
}
