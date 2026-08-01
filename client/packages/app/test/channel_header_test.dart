// SPDX-License-Identifier: Apache-2.0
/// Tests for the channel header's pin pill: a real, live count from
/// `pinsControllerProvider` now, not a permanently disabled dash.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/channel_header.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

Map<String, dynamic> _pinJson(String id) => {
  'id': id,
  'channel_id': 'c1',
  'author_id': 'author-1',
  'author_display_name': 'Priya',
  'seq': 1,
  'content': 'hello',
  'created_at': 0,
  'edited_at': null,
  'pinned_at': 0,
  'pinned_by': 'author-1',
};

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

ProviderContainer _containerWithPins(List<Map<String, dynamic>> pins) {
  return ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            // A batch profile lookup for pin authors answers empty here.
            final body = request.url.path == '/users' ? [] : pins;
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
}

void main() {
  testWidgets('the pin action carries no counter, like its neighbours', (
    tester,
  ) async {
    // It was a bordered pill with a count; two pins must render no "2".
    final container = _containerWithPins([_pinJson('m1'), _pinJson('m2')]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: ChannelHeader(
              channelId: 'c1',
              name: 'general',
              isVoice: false,
              searchOpen: false,
              onToggleSearch: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('-'), findsNothing);
  });

  testWidgets('tapping the pin action opens the pinned messages sheet', (
    tester,
  ) async {
    final container = _containerWithPins([_pinJson('m1')]);
    addTearDown(container.dispose);

    // A real GoRouter, not a bare MaterialApp: opening the sheet reads it before it shows.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: ChannelHeader(
              channelId: 'c1',
              name: 'general',
              isVoice: false,
              searchOpen: false,
              onToggleSearch: () {},
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light, AppTokens.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Pinned messages').first);
    await tester.pumpAndSettle();

    expect(find.text('Pinned messages'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });
}
