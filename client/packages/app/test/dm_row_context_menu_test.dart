// SPDX-License-Identifier: Apache-2.0
/// The DM row's right-click/long-press menu: open, report, and block/unblock
/// the other participant - nothing more, since nothing else about a DM has a
/// real route behind it (see `dm_row.dart`'s own doc comment on why there is
/// no "close" or "hide" item).
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/blocks_controller.dart';
import 'package:slimm_app/src/providers/dms.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/dm_row.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Channel _dm(String id, String name, String peerId) => Channel(
  id: id,
  name: name,
  kind: dmChannelKind,
  createdAt: 0,
  position: 0,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: false,
  dmParticipantId: peerId,
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

ProviderContainer _container({
  List<String> blocked = const [],
  void Function(http.Request request)? onRequest,
}) {
  final db = SlimmDatabase(NativeDatabase.memory());
  return ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      databaseProvider.overrideWith((ref) async {
        ref.onDispose(db.close);
        return db;
      }),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            onRequest?.call(request);
            if (request.url.path == '/blocks') return _json(blocked);
            return http.Response('', 204);
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
}

Widget _harness(ProviderContainer container, GoRouter router) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light, AppTokens.light),
        routerConfig: router,
      ),
    );

GoRouter _router(Channel channel) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          Scaffold(body: DmRow(channel: channel, selected: false)),
    ),
    GoRoute(
      path: '/channels/:channelId',
      builder: (context, state) =>
          Scaffold(body: Text('channel:${state.pathParameters['channelId']}')),
    ),
  ],
);

Future<void> _openMenu(WidgetTester tester) => tester.tapAt(
  tester.getCenter(find.byType(DmRow)),
  buttons: kSecondaryButton,
  kind: PointerDeviceKind.mouse,
);

void main() {
  testWidgets('a right-click offers Open, Report user and Block', (
    tester,
  ) async {
    final channel = _dm('dm-1', 'Priya', 'user-priya');
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container, _router(channel)));
    await tester.pump();

    await _openMenu(tester);
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Report user'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets('an already-blocked peer offers Unblock, not Block again', (
    tester,
  ) async {
    final channel = _dm('dm-1', 'Priya', 'user-priya');
    final container = _container(blocked: const ['user-priya']);
    addTearDown(container.dispose);

    // Lets the block controller's own fetch settle before the menu reads it.
    await container.read(blocksProvider.notifier).refresh();

    await tester.pumpWidget(_harness(container, _router(channel)));
    await tester.pump();

    await _openMenu(tester);
    await tester.pumpAndSettle();

    expect(find.text('Unblock'), findsOneWidget);
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('Open still reaches the channel route from the menu', (
    tester,
  ) async {
    final channel = _dm('dm-1', 'Priya', 'user-priya');
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container, _router(channel)));
    await tester.pump();

    await _openMenu(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('channel:dm-1'), findsOneWidget);
  });
}
