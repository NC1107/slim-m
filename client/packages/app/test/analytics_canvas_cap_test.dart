// SPDX-License-Identifier: Apache-2.0
/// The canvas object cap control on the Space analytics screen: it shows the
/// current cap and patches a new one. Split from analytics_screen_test.dart,
/// which is at its file-size ceiling; the two share the screen but not a file.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/analytics_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

ProviderContainer _containerFor(MockClient client) => ProviderContainer(
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

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: const Scaffold(body: AnalyticsScreen()),
  ),
);

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets('the canvas cap section shows the current cap and patches a new '
      'one', (tester) async {
    var objectCap = 20000;
    final patchedCaps = <int>[];
    final client = MockClient((request) async {
      if (request.url.path == '/space/retention') {
        return _json({'retention_days': 0});
      }
      if (request.url.path == '/space/canvas-cap') {
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          objectCap = body['object_cap'] as int;
          patchedCaps.add(objectCap);
        }
        return _json({'object_cap': objectCap});
      }
      return _json({'enabled': false});
    });
    final container = _containerFor(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.text('Canvas object cap'), findsOneWidget);

    // The section sits below the fold in the test viewport; scroll first.
    await tester.ensureVisible(find.text('5,000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5,000'));
    await tester.pumpAndSettle();

    expect(patchedCaps, [5000]);
  });
}
