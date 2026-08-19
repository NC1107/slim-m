// SPDX-License-Identifier: Apache-2.0
/// The edit-history viewer: the "(edited)" marker opens a sheet listing every
/// version the message has held, oldest first, labelled from Original to
/// Current, and a failed load says so with a retry rather than spinning.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/edit_history_sheet.dart';
import 'package:slimm_app/src/widgets/message_row_parts.dart';
import 'package:slimm_design_system/design_system.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

List<Override> _apiOverrides(
  Future<http.Response> Function(http.Request request) handler,
) => [
  apiProvider.overrideWith((ref) {
    final api = SlimmApi(
      baseUrl: Uri.parse('http://localhost:8080'),
      session: SessionStore(tokens: _tokens),
      httpClient: MockClient(handler),
    );
    ref.onDispose(api.close);
    return api;
  }),
];

Future<void> _pumpAndOpen(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showMessageEditHistorySheet(context, 'c1', 'm1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the marker only fires a tap when given a handler', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Column(
            children: [
              EditedMarker(onTap: () => taps++),
              const EditedMarker(),
            ],
          ),
        ),
      ),
    );

    // Same text twice in tree order: the tappable marker first, the inert one second.
    await tester.tap(find.text('(edited)').first);
    expect(taps, 1);
    // Tapping the handler-less marker does nothing.
    await tester.tap(find.text('(edited)').last);
    expect(taps, 1, reason: 'the inert marker has no tap handler');
  });

  testWidgets('the sheet lists versions oldest first, Original to Current', (
    tester,
  ) async {
    await _pumpAndOpen(
      tester,
      _apiOverrides((request) async {
        expect(request.url.path, '/channels/c1/messages/m1/history');
        return http.Response(
          jsonEncode([
            {'content': 'first draft', 'at': 1000},
            {'content': 'a fix', 'at': 2000},
            {'content': 'final wording', 'at': 3000},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('first draft'), findsOneWidget);
    expect(find.text('a fix'), findsOneWidget);
    expect(find.text('final wording'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    // Oldest first: the original sits above the current in the paint order.
    final originalY = tester.getTopLeft(find.text('first draft')).dy;
    final currentY = tester.getTopLeft(find.text('final wording')).dy;
    expect(originalY, lessThan(currentY));
  });

  testWidgets('a single-version history reads as Current, never Original', (
    tester,
  ) async {
    // A pre-0050 edited message has one element, its current content, and must not read as "Original".
    await _pumpAndOpen(
      tester,
      _apiOverrides(
        (request) async => http.Response(
          jsonEncode([
            {'content': 'the only recorded text', 'at': 1000},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    expect(find.text('the only recorded text'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
  });

  testWidgets('a failed load says so and offers a retry, never spins', (
    tester,
  ) async {
    await _pumpAndOpen(
      tester,
      _apiOverrides((request) async => http.Response('nope', 500)),
    );

    expect(find.text('Could not load edit history.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The retry affordance AppAsyncView renders for a failed load.
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry shows a spinner while it reloads, not a frozen banner', (
    tester,
  ) async {
    var calls = 0;
    final secondLoad = Completer<http.Response>();
    await _pumpAndOpen(
      tester,
      _apiOverrides((request) async {
        calls++;
        // The first load fails; the retry hangs until this test releases it.
        return calls == 1 ? http.Response('nope', 500) : secondLoad.future;
      }),
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    // The reload shows progress, not the stale error banner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Could not load edit history.'), findsNothing);

    secondLoad.complete(
      http.Response(
        jsonEncode([
          {'content': 'loaded on retry', 'at': 1},
        ]),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('loaded on retry'), findsOneWidget);
  });
}
