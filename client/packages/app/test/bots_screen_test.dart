// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The bots pane: creating one reveals its token exactly once, a listing never
/// carries a token, and revoking one keeps it on screen with no live token.
///
/// The reveal is the part worth testing hardest. The server keeps only a hash,
/// so a token lost between the response and the operator's clipboard is a bot
/// that has to be thrown away and made again. That makes "the token is still on
/// screen after a rebuild" a correctness property rather than a nicety.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/bots_screen.dart';
import 'package:slimm_app/src/widgets/toast_overlay.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _botToken = 'slimbot_abcdef0123456789';

String _botJson(
  String username, {
  String? tokenName = 'Helper',
  int? lastUsed,
}) => jsonEncode({
  'user_id': 'bot-$username',
  'username': username,
  'display_name': username,
  'created_at': 0,
  'token_name': tokenName,
  'token_last_used_at': lastUsed,
});

Future<void> _pump(
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
        home: const BotsScreen(),
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned.fill(child: ToastOverlay()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creating a bot shows its token, and keeps showing it', (
    tester,
  ) async {
    var created = false;
    await _pump(tester, (request) {
      if (request.method == 'POST' && request.url.path == '/bots') {
        created = true;
        return http.Response(
          jsonEncode({
            'bot': jsonDecode(_botJson('helper')),
            'token': _botToken,
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/bots') {
        return http.Response(
          created ? '[${_botJson('helper')}]' : '[]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await tester.enterText(find.byType(TextField).first, 'helper');
    await tester.tap(find.widgetWithText(AppButton, 'Create bot'));
    await tester.pumpAndSettle();

    expect(find.text(_botToken), findsOneWidget);

    // A rebuild must not take it away; there is no second chance to read it.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(_botToken), findsOneWidget);
  });

  testWidgets('the token is dismissed only when the operator says so', (
    tester,
  ) async {
    await _pump(tester, (request) {
      if (request.method == 'POST' && request.url.path == '/bots') {
        return http.Response(
          jsonEncode({
            'bot': jsonDecode(_botJson('helper')),
            'token': _botToken,
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '[]',
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    await tester.enterText(find.byType(TextField).first, 'helper');
    await tester.tap(find.widgetWithText(AppButton, 'Create bot'));
    await tester.pumpAndSettle();
    expect(find.text(_botToken), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text(_botToken), findsNothing);
  });

  testWidgets('a listed bot never shows a token, only whether it has one', (
    tester,
  ) async {
    await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/bots') {
        return http.Response(
          '[${_botJson('helper', lastUsed: 1000)}]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    expect(find.text('@helper'), findsOneWidget);
    expect(find.text('Token active.'), findsOneWidget);
    expect(
      find.textContaining('slimbot_'),
      findsNothing,
      reason:
          'the listing response carries no token, so nothing can render one',
    );
  });

  testWidgets('a revoked bot stays listed, with no Revoke button left', (
    tester,
  ) async {
    await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/bots') {
        return http.Response(
          '[${_botJson('helper', tokenName: null)}]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    expect(
      find.text('@helper'),
      findsOneWidget,
      reason: 'the account stays, so what it wrote stays attributed to it',
    );
    expect(find.text('Revoked. Kept for what it wrote.'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Revoke'), findsNothing);
  });

  testWidgets('revoking posts to the revoke route for that bot', (
    tester,
  ) async {
    final posted = <String>[];
    await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/bots') {
        return http.Response(
          '[${_botJson('helper')}]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST') {
        posted.add(request.url.path);
        return http.Response('', 204);
      }
      return http.Response('{}', 200);
    });

    await tester.tap(find.widgetWithText(AppButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(posted, ['/bots/bot-helper/revoke']);
  });
}
