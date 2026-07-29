// SPDX-License-Identifier: Apache-2.0
/// Tests for the shell's width-driven layout: the member pane must not
/// merely be styled as hidden, it must not be built at all below expanded
/// width, and must appear once the window is wide enough.
///
/// Plus the compact layout's own regression: `ChannelHeader` is never built
/// at that width, and it used to be the only host of in-channel search, the
/// pinned-messages sheet, the channel topic and the member list, so all four
/// were unreachable on a phone. Each has a test here that drives the app bar
/// the way a thumb would.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_app/src/widgets/channel_search.dart';
import 'package:slimm_app/src/widgets/member_pane.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// Stands in for the real [SyncController], which opens a websocket to a
/// server that does not exist here. `start` is called from the base
/// constructor, but Dart dispatches virtually even there, so overriding it as
/// a no-op keeps the real one from ever touching the network.
class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

/// The compact tests render a real conversation, which fetches its members,
/// its pins and a window of messages on the way up. None of the three is what
/// those tests are about, so they all answer empty rather than failing: an
/// error state would still prove reachability, but it would also hide a
/// widget that only builds on success.
MockClient _quietClient() => MockClient((request) async {
  final body = request.url.path == '/me'
      ? {
          'id': 'bob',
          'username': 'bob',
          'display_name': 'Bob',
          'created_at': 0,
          'permissions': 0,
        }
      : const <Object>[];
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
});

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A container wired like the app's, with the network swapped for the given
/// client (by default an always-failing one: every provider that reads it
/// already degrades to an honest loading/error state rather than crashing)
/// and the database swapped for an in-memory one this test closes itself, on
/// the same clock the test binding uses; see [_teardown] for why that matters.
({ProviderContainer container, SlimmDatabase db}) _setup({
  MockClient? httpClient,
  bool signedIn = false,
}) {
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      // Every authenticated call refuses before it reaches the transport
      // otherwise, which would leave the pin count reading "loading" forever.
      if (signedIn)
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      syncControllerProvider.overrideWith(_NoopSyncController.new),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient:
              httpClient ??
              MockClient(
                (_) async => throw StateError('no network in this test'),
              ),
        );
        ref.onDispose(client.close);
        return client;
      }),
      databaseProvider.overrideWith((ref) => db),
    ],
  );
  return (container: container, db: db);
}

/// Drift keeps a query stream's cache alive briefly after its last listener
/// unsubscribes, using a timer it documents itself as the reason "Flutter
/// throws an exception when timers remain after a test run". Unmounting
/// first (so the rail's `StreamBuilder`s actually unsubscribe) and pumping
/// past that timer before disposing is what keeps this test from either
/// tripping that assertion or hanging forever waiting on a timer the fake
/// test clock never advances on its own.
Future<void> _teardown(
  WidgetTester tester,
  ProviderContainer container,
  SlimmDatabase db,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  container.dispose();
  await db.close();
}

/// Bypasses the real app router (which redirects a signed-out session to
/// onboarding, which is not what this test is about) with a router that
/// unconditionally shows [HomeShell], nesting the conversation route under
/// the shell exactly as `router.dart` does.
GoRouter _testRouter(String location) => GoRouter(
  initialLocation: location,
  routes: [
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(
          path: '/channels',
          builder: (context, state) =>
              const Center(child: Text('conversation')),
          routes: [
            GoRoute(
              path: ':channelId',
              builder: (context, state) => ConversationPane(
                channelId: state.pathParameters['channelId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _pumpAtWidth(
  WidgetTester tester,
  ProviderContainer container,
  double width, {
  String location = '/channels',
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light, AppTokens.light),
        routerConfig: _testRouter(location),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A phone-width shell with one channel open, seeded so the app bar has a
/// real name and topic to show.
Future<({ProviderContainer container, SlimmDatabase db})> _pumpCompactChannel(
  WidgetTester tester,
) async {
  final setup = _setup(httpClient: _quietClient(), signedIn: true);
  await MessageStore(setup.db).upsertChannels([
    const api.Channel(
      id: 'c1',
      name: 'general',
      kind: 'text',
      createdAt: 0,
      topic: 'Anything and everything',
    ),
  ]);
  await _pumpAtWidth(tester, setup.container, 500, location: '/channels/c1');
  return setup;
}

void main() {
  testWidgets('the member pane is absent below expanded width', (tester) async {
    final setup = _setup();
    await _pumpAtWidth(
      tester,
      setup.container,
      700,
    ); // medium: two panes, no member pane.
    expect(find.byType(AppMemberPane), findsNothing);
    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('the member pane appears at expanded width', (tester) async {
    final setup = _setup();
    await _pumpAtWidth(tester, setup.container, 1400);
    expect(find.byType(AppMemberPane), findsOneWidget);
    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets(
    'the member toggle shows only where the pane can, not at medium width',
    (tester) async {
      final setup = _setup(httpClient: _quietClient(), signedIn: true);
      await MessageStore(setup.db).upsertChannels([
        const api.Channel(
          id: 'c1',
          name: 'general',
          kind: 'text',
          createdAt: 0,
        ),
      ]);

      // Expanded: the pane can show, so the header offers its toggle.
      await _pumpAtWidth(
        tester,
        setup.container,
        1400,
        location: '/channels/c1',
      );
      expect(find.bySemanticsLabel('Toggle member list'), findsOneWidget);

      // Medium: the pane never shows here, so a lit toggle over it would lie.
      await _pumpAtWidth(
        tester,
        setup.container,
        700,
        location: '/channels/c1',
      );
      expect(find.byType(AppMemberPane), findsNothing);
      expect(find.bySemanticsLabel('Toggle member list'), findsNothing);

      await _teardown(tester, setup.container, setup.db);
    },
  );

  testWidgets(
    'hiding the pane at expanded width removes it, not just styles it',
    (tester) async {
      final setup = _setup();
      await _pumpAtWidth(tester, setup.container, 1400);
      expect(find.byType(AppMemberPane), findsOneWidget);

      setup.container.read(memberPaneVisibleProvider.notifier).state = false;
      await tester.pumpAndSettle();
      expect(find.byType(AppMemberPane), findsNothing);

      await _teardown(tester, setup.container, setup.db);
    },
  );

  testWidgets('the channel topic is on screen at compact width', (
    tester,
  ) async {
    final setup = await _pumpCompactChannel(tester);

    expect(find.text('general'), findsOneWidget);
    expect(
      find.text('Anything and everything'),
      findsOneWidget,
      reason:
          'the topic only ever lived in ChannelHeader, which this '
          'width never builds',
    );

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('search opens from the compact app bar', (tester) async {
    final setup = await _pumpCompactChannel(tester);

    expect(find.byType(ChannelSearchBar), findsNothing);
    await tester.tap(find.bySemanticsLabel('Search messages'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelSearchBar), findsOneWidget);

    // And closes again, since the same control is the only way back.
    await tester.tap(find.bySemanticsLabel('Search messages'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelSearchBar), findsNothing);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('the pinned-messages sheet opens from the compact app bar', (
    tester,
  ) async {
    final setup = await _pumpCompactChannel(tester);

    await tester.tap(find.bySemanticsLabel('Pinned messages, 0'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned messages'), findsOneWidget);
    expect(find.text('Nothing pinned yet.'), findsOneWidget);

    // Dismissed before teardown so the route stack unwinds normally.
    Navigator.of(tester.element(find.text('Pinned messages'))).pop();
    await tester.pumpAndSettle();

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('the member list opens from the compact app bar', (tester) async {
    final setup = await _pumpCompactChannel(tester);

    expect(find.byType(AppMemberPane), findsNothing);
    await tester.tap(find.bySemanticsLabel('Show members'));
    await tester.pumpAndSettle();
    expect(
      find.byType(AppMemberPane),
      findsOneWidget,
      reason:
          'the roster has no room to dock beside the conversation at '
          'this width, so the app bar has to summon it',
    );

    await _teardown(tester, setup.container, setup.db);
  });
}
