// SPDX-License-Identifier: Apache-2.0
/// The Space analytics screen: the toggle, the off notice, and that the
/// headline numbers are visible text rather than only pixels in a chart.
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
import 'package:slimm_app/src/widgets/analytics_bar_chart.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _enabledBody = {
  'enabled': true,
  'stats': {
    'total_messages': 42,
    'member_count': 3,
    'channel_count': 2,
    'attachment_bytes': 2048,
    'messages_by_day': [
      {'date': '2026-08-01', 'count': 5},
      {'date': '2026-08-02', 'count': 9},
    ],
    'active_hours': [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
      0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ],
    'memory_samples': [
      {'sampled_at': 1000, 'rss_bytes': 7000000},
    ],
  },
};

ProviderContainer _containerFor(MockClient client) {
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
  return container;
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: const Scaffold(body: AnalyticsScreen()),
  ),
);

void main() {
  testWidgets('off by default: the notice shows and no stat is computed', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'enabled': false}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final container = _containerFor(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.textContaining('Analytics is off'), findsOneWidget);
    expect(find.textContaining('Total messages'), findsNothing);
    expect(find.byType(AnalyticsBarChart), findsNothing);
  });

  testWidgets('turning it on sends enabled: true and the screen shows stats', (
    tester,
  ) async {
    var enabled = false;
    final patchedBodies = <Map<String, dynamic>>[];

    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        patchedBodies.add(body);
        enabled = body['enabled'] as bool;
      }
      return http.Response(
        jsonEncode(enabled ? _enabledBody : {'enabled': false}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final container = _containerFor(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppToggle));
    await tester.pumpAndSettle();

    expect(patchedBodies, [
      {'enabled': true},
    ]);
    expect(find.textContaining('Analytics is off'), findsNothing);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets(
    'an enabled deployment shows the numbers as text, not only a chart',
    (tester) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_enabledBody),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final container = _containerFor(client);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      // The four stat tiles, as visible text.
      expect(find.text('42'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);

      // A screen reader gets the series as text, not only the chart's pixels.
      final daySemantics = tester.getSemantics(
        find.byType(AnalyticsBarChart).first,
      );
      expect(daySemantics.label, contains('2026-08-01: 5'));
      expect(daySemantics.label, contains('2026-08-02: 9'));
    },
  );
}
