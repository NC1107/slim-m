// SPDX-License-Identifier: Apache-2.0
/// Tests for channel rename/topic and deletion from the rail: gating on
/// `canManage`, and the Channel settings screen's round trip through the API
/// and the local store (`channel_settings_screen.dart`, which replaced the
/// old manage-channel sheet these tests used to drive directly). Creation
/// moved to `SpaceMenuButton` (backlog item 55); its own round trip through
/// the create sheet is `space_menu_button_test.dart`. Per-section permission
/// gating is `channel_settings_screen_test.dart`'s own concern.
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
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/routing/modal_page.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_app/src/screens/channel_settings_screen.dart';
import 'package:slimm_app/src/widgets/channel_rail.dart' show channelIdInPath;
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

Channel _channel(
  String id,
  String name, {
  String kind = 'text',
  String? topic,
  String? categoryId,
}) => Channel(
  id: id,
  name: name,
  kind: kind,
  createdAt: 0,
  position: 0,
  topic: topic,
  categoryId: categoryId,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: false,
);

/// Wraps [child] with everything a sheet or the Channel settings screen's
/// provider reads need: a session, a caller with [permissions] (the settings
/// screen gates its own sections on `meProvider`, unlike the old sheet which
/// took `canManage` as a plain widget prop), an [apiProvider] backed by
/// [handler], an in-memory local store, and a real [GoRouter] (the create
/// sheet navigates to the new channel, and a deletion that closes the open
/// channel navigates back to the list, both through `GoRouter.of(context)`).
Widget _harness(
  Widget child, {
  required http.Response Function(http.Request) handler,
  String initialLocation = '/',
  int permissions = Perm.manageChannels,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        path: Routes.channels,
        builder: (context, state) => Scaffold(body: child),
      ),
      // The section stays mounted with a channel open, so a delete from Channel settings shows against the pane behind it.
      GoRoute(
        path: Routes.channelPattern,
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              Text('channel:${state.pathParameters['channelId']}'),
              Expanded(child: child),
            ],
          ),
        ),
      ),
      GoRoute(
        path: Routes.channelSettings,
        pageBuilder: (context, state) => modalPage(
          context,
          ChannelSettingsScreen(args: state.extra as ChannelSettingsRouteArgs?),
        ),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
        meProvider.overrideWith(
          (ref) async => Me(
            id: 'user-1',
            username: 'user-1',
            displayName: 'User',
            createdAt: 0,
            permissions: permissions,
          ),
        ),
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
      ],
    ),
    child: MaterialApp.router(
      theme: buildTheme(Brightness.light, AppTokens.light),
      routerConfig: router,
    ),
  );
}

void main() {
  group('section header (backlog item 55)', () {
    testWidgets('the uncategorised section reads CHANNELS, the same treatment '
        'DirectMessagesSection gives its own header - it used to be a blank '
        'label with a floating "+" and no explanation', (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.bySemanticsLabel('Channels'), findsOneWidget);
    });

    testWidgets('a named category keeps showing its own name above it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general', categoryId: 'cat-1')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
            ],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('TEXT'), findsOneWidget);
    });

    testWidgets('an empty category is hidden from a member: migration 0031 '
        'seeds Text and Voice unconditionally, so every fresh deployment '
        'rendered two dead headers under the populated one', (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
              ChannelCategoryRow(id: 'cat-2', name: 'Voice', position: 1),
            ],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.text('TEXT'), findsNothing);
      expect(find.text('VOICE'), findsNothing);
    });

    testWidgets('a manager keeps the empty category, as a drop target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
            ],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('TEXT'), findsOneWidget);
    });
  });

  group('gating on canManage', () {
    testWidgets('a member without MANAGE_CHANNELS sees a read-only list', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Manage general'), findsNothing);
    });

    testWidgets('a manager sees a per-row manage button', (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Manage general'), findsOneWidget);
    });
  });

  group('channel settings: general and danger zone', () {
    testWidgets('the last-channel refusal explains itself rather than '
        'showing the bare server error', (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (request) => request.method == 'DELETE'
              ? http.Response(
                  jsonEncode({
                    'error': "cannot delete the deployment's last channel",
                  }),
                  409,
                )
              : http.Response('{}', 200),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Manage general'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last channel here'), findsOneWidget);
      expect(
        find.textContaining("deployment's last channel"),
        findsNothing,
        reason: 'the raw server wording should not reach the screen',
      );
    });

    testWidgets('saving the name and topic sends a PATCH and stays open, '
        'unlike the old sheet which closed', (tester) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (request) {
            requests.add(request);
            return request.method == 'PATCH'
                ? http.Response(
                    jsonEncode({
                      'id': 'c1',
                      'name': 'renamed',
                      'kind': 'text',
                      'created_at': 0,
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  )
                : http.Response('{}', 200);
          },
        ),
      );

      await tester.tap(find.bySemanticsLabel('Manage general'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings...'));
      await tester.pumpAndSettle();

      await tester.enterText(find.bySemanticsLabel('Channel name'), 'renamed');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(
        requests.where((r) => r.method == 'PATCH').map((r) => r.url.path),
        ['/channels/c1'],
      );
      expect(
        find.text('Channel settings'),
        findsOneWidget,
        reason: 'a save is not a delete: the screen stays open afterward',
      );
      expect(
        find.widgetWithText(AppButton, 'Save changes'),
        findsOneWidget,
        reason:
            'the button must reset to its resting label, not stay '
            '"Saving..."',
      );
      // Drains the success toast's dismiss timer so it is not pending at teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('deleting the open channel closes the screen and leaves it', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general'), _channel('c2', 'random')],
            categories: const [],
            selectedId: 'c1',
            canManage: true,
            onReorder: (_) {},
          ),
          initialLocation: Routes.channel('c1'),
          handler: (request) {
            requests.add(request);
            return request.method == 'DELETE'
                ? http.Response('', 204)
                : http.Response('{}', 200);
          },
        ),
      );
      expect(find.text('channel:c1'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Manage general'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(
        requests.where((r) => r.method == 'DELETE').map((r) => r.url.path),
        ['/channels/c1'],
      );
      expect(
        find.text('Channel settings'),
        findsNothing,
        reason: 'the screen must close once the delete has landed',
      );
      expect(
        find.text('channel:c1'),
        findsNothing,
        reason: 'the pane must leave a channel that no longer exists',
      );
    });

    testWidgets('the delete dialog names its way out, and taking it deletes '
        'nothing', (tester) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general'), _channel('c2', 'random')],
            categories: const [],
            selectedId: 'c1',
            canManage: true,
            onReorder: (_) {},
          ),
          initialLocation: Routes.channel('c1'),
          handler: (request) {
            requests.add(request);
            return http.Response('{}', 200);
          },
        ),
      );

      await tester.tap(find.bySemanticsLabel('Manage general'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete channel'));
      await tester.pumpAndSettle();

      // "Keep channel", not "Cancel": next to "Delete permanently" the vaguer
      // word is what made this dialog get copied instead of reused.
      expect(find.text('Keep channel'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);

      await tester.tap(find.text('Keep channel'));
      await tester.pumpAndSettle();

      expect(
        requests.where((r) => r.method == 'DELETE'),
        isEmpty,
        reason: 'backing out must not delete anything',
      );
      expect(
        find.text('channel:c1'),
        findsOneWidget,
        reason: 'the channel is still open',
      );
    });

    testWidgets('deleting a channel that is not open still closes the screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general'), _channel('c2', 'random')],
            categories: const [],
            selectedId: 'c1',
            canManage: true,
            onReorder: (_) {},
          ),
          initialLocation: Routes.channel('c1'),
          handler: (request) => request.method == 'DELETE'
              ? http.Response('', 204)
              : http.Response('{}', 200),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Manage random'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel settings...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(
        find.text('Channel settings'),
        findsNothing,
        reason: 'the screen must close for any channel, not just the open one',
      );
      expect(
        find.text('channel:c1'),
        findsOneWidget,
        reason: 'deleting another channel must not navigate away',
      );
    });
  });

  group('channelIdInPath', () {
    test('reads the id only from a channel route', () {
      expect(channelIdInPath('/channels/c1'), 'c1');
      expect(channelIdInPath('/channels'), isNull);
      expect(channelIdInPath('/channels/'), isNull);
      expect(channelIdInPath('/settings'), isNull);
    });
  });
}
