// SPDX-License-Identifier: Apache-2.0
/// The "do not wake me for ordinary chatter overnight" row
/// `NotificationsSection` gained: it reads the real window back from
/// `GET /push/quiet-hours`, turning it on sends a `PUT` and turning it off
/// sends a `DELETE`, and a server too old to have the route (a plain 404)
/// makes the row disappear rather than offering a toggle that would just
/// fail. Mirrors `notification_preference_row_test.dart`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/personal_status_sections.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const Scaffold(body: NotificationsSection()),
  ),
);

ProviderContainer _containerWith(
  Future<http.Response> Function(http.Request) handler,
) {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient(handler),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
  return container;
}

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// The quiet-hours toggle by its accessible name, the same
/// [AppToggle.semanticLabel] predicate
/// `notifications_section_sound_toggle_test.dart` uses for its own toggle:
/// [AppToggle] is not a Material [Switch], so a bare type finder cannot
/// distinguish it from the section's other toggles.
final _quietHoursToggleFinder = find.byWidgetPredicate(
  (w) => w is AppToggle && w.semanticLabel == 'Quiet hours',
);

/// Every other row this section renders needs a non-404 answer or the whole
/// section throws building around it; only `/push/preference` and
/// `/push/quiet-hours` vary per test.
http.Response? _commonStub(http.Request request) {
  if (request.url.path == '/push/preference') {
    return _json({'preference': 'everything'});
  }
  return null;
}

void main() {
  testWidgets('shows the window GET /push/quiet-hours answers with', (
    tester,
  ) async {
    final container = _containerWith((request) async {
      final common = _commonStub(request);
      if (common != null) return common;
      if (request.url.path == '/push/quiet-hours') {
        return _json({
          'quiet_hours': {'start_minute': 23 * 60, 'end_minute': 8 * 60},
        });
      }
      return http.Response('', 404);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
  });

  testWidgets('a disabled window (null) hides the start and end rows', (
    tester,
  ) async {
    final container = _containerWith((request) async {
      final common = _commonStub(request);
      if (common != null) return common;
      if (request.url.path == '/push/quiet-hours') {
        return _json({'quiet_hours': null});
      }
      return http.Response('', 404);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Quiet hours'), findsOneWidget);
    expect(find.text('Starts'), findsNothing);
    expect(find.text('Ends'), findsNothing);
  });

  testWidgets('turning the toggle on sends a PUT with a window', (
    tester,
  ) async {
    Map<String, dynamic>? stored;
    final requests = <String>[];
    final container = _containerWith((request) async {
      final common = _commonStub(request);
      if (common != null) return common;
      if (request.url.path != '/push/quiet-hours') {
        return http.Response('', 404);
      }
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'PUT') {
        // The PUT response body is the flat QuietHours object, unlike GET's `quiet_hours`-wrapped one.
        stored = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(stored!);
      }
      return _json({'quiet_hours': stored});
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    expect(find.text('Starts'), findsNothing);

    await tester.tap(_quietHoursToggleFinder);
    await tester.pumpAndSettle();

    expect(requests, contains('PUT /push/quiet-hours'));
    expect(stored, isNotNull);
    expect(stored!['start_minute'], isA<int>());
    expect(stored!['end_minute'], isA<int>());
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
  });

  testWidgets('turning the toggle off sends a DELETE', (tester) async {
    var enabled = true;
    final requests = <String>[];
    final container = _containerWith((request) async {
      final common = _commonStub(request);
      if (common != null) return common;
      if (request.url.path != '/push/quiet-hours') {
        return http.Response('', 404);
      }
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'DELETE') {
        enabled = false;
        return http.Response('', 204);
      }
      return enabled
          ? _json({
              'quiet_hours': {'start_minute': 23 * 60, 'end_minute': 8 * 60},
            })
          : _json({'quiet_hours': null});
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    expect(find.text('Starts'), findsOneWidget);

    await tester.tap(_quietHoursToggleFinder);
    await tester.pumpAndSettle();

    expect(requests, contains('DELETE /push/quiet-hours'));
    expect(find.text('Starts'), findsNothing);
  });

  testWidgets(
    'a server predating the route (a bare 404) hides the row entirely',
    (tester) async {
      final container = _containerWith((request) async {
        final common = _commonStub(request);
        if (common != null) return common;
        return http.Response('', 404);
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Quiet hours'), findsNothing);
    },
  );
}
