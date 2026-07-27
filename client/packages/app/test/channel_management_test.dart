// SPDX-License-Identifier: Apache-2.0
/// Tests for channel creation, rename/topic, and deletion from the rail:
/// gating on `canManage`, and the create sheet's round trip through the API
/// and the local store.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' hide Channel;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Channel _channel(String id, String name,
        {String kind = 'text', String? topic}) =>
    Channel(
      id: id,
      name: name,
      kind: kind,
      createdAt: 0,
      topic: topic,
      cursor: 0,
      lastReadSeq: 0,
    );

/// Wraps [child] with everything a sheet's provider reads need: a session,
/// an [apiProvider] backed by [handler], an in-memory local store, and a
/// real [GoRouter] (the create sheet navigates to the new channel, and a
/// deletion that closes the open channel navigates back to the list, both
/// through `GoRouter.of(context)`).
Widget _harness(Widget child,
    {required http.Response Function(http.Request) handler}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: child)),
      GoRoute(
        path: '/channels/:channelId',
        builder: (context, state) => Scaffold(
          body: Text('channel:${state.pathParameters['channelId']}'),
        ),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: ProviderContainer(overrides: [
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
      storeProvider.overrideWith((ref) async {
        final db = SlimmDatabase(NativeDatabase.memory());
        ref.onDispose(db.close);
        return MessageStore(db);
      }),
    ]),
    child: MaterialApp.router(
      theme: buildTheme(Brightness.light, AppTokens.light),
      routerConfig: router,
    ),
  );
}

void main() {
  group('gating on canManage', () {
    testWidgets('a member without MANAGE_CHANNELS sees a read-only list',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          TextChannelsSection(
            channels: [_channel('c1', 'general')],
            selectedId: null,
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Create a text channel'), findsNothing);
      expect(find.bySemanticsLabel('Manage general'), findsNothing);
    });

    testWidgets(
        'a manager sees the section add button and a per-row manage button',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          TextChannelsSection(
            channels: [_channel('c1', 'general')],
            selectedId: null,
            canManage: true,
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Create a text channel'), findsOneWidget);
      expect(find.bySemanticsLabel('Manage general'), findsOneWidget);
    });
  });

  group('create channel sheet', () {
    testWidgets('creating a channel posts the name and kind, then closes',
        (tester) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        _harness(
          TextChannelsSection(
            channels: const [],
            selectedId: null,
            canManage: true,
          ),
          handler: (request) {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'id': 'new-1',
                'name': 'roadmap',
                'kind': 'text',
                'topic': null,
                'created_at': 1,
              }),
              200,
            );
          },
        ),
      );

      await tester.tap(find.bySemanticsLabel('Create a text channel'));
      await tester.pumpAndSettle();
      expect(find.text('Create a channel'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'roadmap');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Create channel'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/channels');
      expect(jsonDecode(requests.single.body),
          {'name': 'roadmap', 'kind': 'text'});
      // The sheet closes on success rather than lingering over a done form.
      expect(find.text('Create a channel'), findsNothing);
    });
  });

  group('manage channel sheet', () {
    testWidgets(
        'the last-channel refusal explains itself rather than '
        'showing the bare server error', (tester) async {
      await tester.pumpWidget(
        _harness(
          TextChannelsSection(
            channels: [_channel('c1', 'general')],
            selectedId: null,
            canManage: true,
          ),
          handler: (request) => request.method == 'DELETE'
              ? http.Response(
                  jsonEncode(
                      {'error': "cannot delete the deployment's last channel"}),
                  409,
                )
              : http.Response('{}', 200),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Manage general'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last channel here'), findsOneWidget);
      expect(find.textContaining("deployment's last channel"), findsNothing,
          reason: 'the raw server wording should not reach the screen');
    });
  });
}
