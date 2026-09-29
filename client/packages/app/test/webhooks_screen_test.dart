// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The webhooks pane: rotating one reveals its new URL once, and the list says
/// how long ago each webhook last delivered.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/webhooks_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

String _webhookJson({int? lastDeliveryAt}) => jsonEncode({
  'id': 'wh-1',
  'channel_id': 'chan-1',
  'label': 'sonarr',
  'created_at': 0,
  'last_delivery_at': lastDeliveryAt,
  'created_by_display_name': 'root',
});

Future<void> _pump(
  WidgetTester tester,
  http.Response Function(http.Request) handler,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
        home: const WebhooksScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _json = {'content-type': 'application/json'};

void main() {
  test('the last-delivery label reads as a recency, not a bare fact', () {
    final now = DateTime.fromMillisecondsSinceEpoch(10 * 24 * 3600 * 1000);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    expect(
      webhookDeliveryLabel(ago(const Duration(seconds: 5)), now),
      'Last delivered just now',
    );
    expect(
      webhookDeliveryLabel(ago(const Duration(minutes: 7)), now),
      'Last delivered 7m ago',
    );
    expect(
      webhookDeliveryLabel(ago(const Duration(hours: 3)), now),
      'Last delivered 3h ago',
    );
    expect(
      webhookDeliveryLabel(ago(const Duration(days: 4)), now),
      'Last delivered 4d ago',
    );
  });

  testWidgets('rotating posts to the rotate route and reveals the new URL', (
    tester,
  ) async {
    final posted = <String>[];
    await _pump(tester, (request) {
      if (request.method == 'GET' && request.url.path == '/webhooks') {
        return http.Response('[${_webhookJson()}]', 200, headers: _json);
      }
      if (request.method == 'POST') {
        posted.add(request.url.path);
        return http.Response(
          jsonEncode({
            'webhook': jsonDecode(_webhookJson()),
            'delivery_path': '/webhooks/wh-1/fresh-token',
          }),
          200,
          headers: _json,
        );
      }
      return http.Response('{}', 200);
    });

    expect(find.text('Never delivered yet.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Rotate sonarr'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Rotate').last);
    await tester.pumpAndSettle();

    expect(posted, ['/webhooks/wh-1/rotate']);
    expect(
      find.text('http://localhost:8080/webhooks/wh-1/fresh-token'),
      findsOneWidget,
    );
  });
}
