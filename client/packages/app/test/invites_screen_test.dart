// SPDX-License-Identifier: Apache-2.0
/// Tests for the invites screen: creating one posts the chosen options, and
/// revoking one is gated behind a confirmation that actually says what
/// happens, matching `confirm_dialog.dart`'s contract.
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
import 'package:slimm_app/src/screens/admin/invites_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

String _inviteJson(String code, {bool revoked = false}) => jsonEncode({
  'code': code,
  'max_uses': null,
  'uses': 0,
  'expires_at': null,
  'created_at': 0,
  'revoked': revoked,
  'usable': !revoked,
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
        home: const InvitesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'revoking an invite is blocked until the confirmation is accepted',
    (tester) async {
      final deletes = <Uri>[];
      var listed = false;
      await _pump(tester, (request) {
        if (request.method == 'GET' && request.url.path == '/invites') {
          listed = true;
          return http.Response(
            '[${_inviteJson('welcome-123')}]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          deletes.add(request.url);
          return http.Response('', 204);
        }
        return http.Response(
          '{}',
          404,
          headers: {'content-type': 'application/json'},
        );
      });
      expect(listed, isTrue);
      expect(find.text('welcome-123'), findsOneWidget);

      // Cancelling leaves the invite alone: no DELETE is ever sent.
      await tester.tap(find.byIcon(AppIcons.revoke));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletes, isEmpty);
      expect(find.text('welcome-123'), findsOneWidget);

      // Confirming sends exactly one DELETE for the code shown.
      await tester.tap(find.byIcon(AppIcons.revoke));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(deletes, hasLength(1));
      expect(deletes.single.path, '/invites/welcome-123');
    },
  );

  testWidgets('creating an invite posts the chosen uses and shows the code', (
    tester,
  ) async {
    final posts = <(Uri, Map<String, dynamic>)>[];
    await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/invites') {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path == '/invites') {
        posts.add((
          request.url,
          jsonDecode(request.body) as Map<String, dynamic>,
        ));
        return http.Response(
          _inviteJson('fresh-code'),
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

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.tap(find.text('Create invite'));
    await tester.pumpAndSettle();

    expect(posts, hasLength(1));
    expect(posts.single.$2, {'max_uses': 5});
    expect(find.text('fresh-code'), findsOneWidget);
  });

  /// The create card used to render `e.message` in a `SnackBar`, so a
  /// dropped connection surfaced its own Dart exception string.
  testWidgets(
    'a create that cannot reach the server shows a safe sentence inline',
    (tester) async {
      await _pump(tester, (request) {
        if (request.method == 'GET' && request.url.path == '/invites') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/invites') {
          throw const SocketException('connection refused');
        }
        return http.Response(
          '{}',
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.tap(find.text('Create invite'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(
        find.textContaining('the server could not be reached'),
        findsOneWidget,
      );
    },
  );
}
