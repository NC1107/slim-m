// SPDX-License-Identifier: Apache-2.0
/// Tests for the command palette: opening it (by key and by tap), grouped
/// results, keyboard navigation, and that closing it restores focus.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_app/src/widgets/command_palette.dart';
import 'package:slimm_app/src/widgets/member_pane.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _me = api.Me(
  id: 'self',
  username: 'self',
  displayName: 'Self',
  createdAt: 0,
  permissions: 0,
);

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

api.UserProfile _profile(String id, String name) => api.UserProfile(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  createdAt: 0,
);

/// Everything but `/dms/*` throws, matching the rest of this test suite's
/// convention of an otherwise-always-failing client so an unexpected call
/// surfaces immediately instead of returning something plausible-looking.
http.Client _fakeClient() => MockClient((request) async {
  if (request.method == 'POST' && request.url.path == '/dms/other') {
    return http.Response(
      jsonEncode({
        'channel_id': 'dm-1',
        'user': {
          'id': 'other',
          'username': 'ren',
          'display_name': 'Ren',
          'created_at': 0,
        },
        'unread': 0,
        'created_at': 0,
      }),
      200,
    );
  }
  throw StateError('unexpected request in this test: ${request.url}');
});

({ProviderContainer container, SlimmDatabase db}) _setup() {
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: _fakeClient(),
        );
        ref.onDispose(client.close);
        return client;
      }),
      databaseProvider.overrideWith((ref) => db),
      meProvider.overrideWith((ref) async => _me),
      membersProvider.overrideWith((ref) async => [_profile('other', 'Ren')]),
    ],
  );
  return (container: container, db: db);
}

/// See home_shell_test.dart for why unmounting and pumping past Drift's
/// stream-cache timer, before disposing, is required here.
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

GoRouter _testRouter() => GoRouter(
  initialLocation: '/channels',
  routes: [
    GoRoute(
      path: '/channels',
      builder: (context, state) =>
          const HomeShell(child: Center(child: Text('conversation'))),
    ),
    GoRoute(
      path: Routes.channelPattern,
      builder: (context, state) =>
          const HomeShell(child: Center(child: Text('conversation'))),
    ),
    GoRoute(
      path: Routes.settings,
      builder: (context, state) =>
          const Scaffold(body: Text('settings-screen')),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light, AppTokens.light),
        routerConfig: _testRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressCtrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// A channel or member name the palette shows can also be on screen behind
/// it (the rail, the member pane), so tests scope the search to the
/// palette's own floating card rather than matching either copy.
Finder _inPalette(String text) =>
    find.descendant(of: find.byType(AppMenu), matching: find.text(text));

void main() {
  testWidgets('Ctrl+K opens the command palette', (tester) async {
    final setup = _setup();
    await MessageStore(setup.db).upsertChannels(const [
      api.Channel(id: 'ch1', name: 'general', kind: 'text', createdAt: 0),
    ]);
    await _pump(tester, setup.container);

    expect(find.byKey(const Key('command-palette-input')), findsNothing);
    await _pressCtrlK(tester);
    expect(find.byKey(const Key('command-palette-input')), findsOneWidget);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('tapping the rail search field opens the command palette', (
    tester,
  ) async {
    final setup = _setup();
    await _pump(tester, setup.container);

    await tester.tap(find.byKey(const Key('rail-search-trigger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('command-palette-input')), findsOneWidget);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('results are grouped, and typing narrows them', (tester) async {
    final setup = _setup();
    await MessageStore(setup.db).upsertChannels(const [
      api.Channel(id: 'ch1', name: 'general', kind: 'text', createdAt: 0),
    ]);
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);

    expect(find.text('CHANNELS'), findsOneWidget);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(_inPalette('general'), findsOneWidget);
    expect(_inPalette('Ren'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('command-palette-input')),
      'zzz-no-match',
    );
    await tester.pumpAndSettle();
    expect(_inPalette('general'), findsNothing);
    expect(_inPalette('Ren'), findsNothing);
    expect(find.text('No matches.'), findsOneWidget);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('selecting a channel result navigates to it and closes', (
    tester,
  ) async {
    final setup = _setup();
    await MessageStore(setup.db).upsertChannels(const [
      api.Channel(id: 'ch1', name: 'general', kind: 'text', createdAt: 0),
    ]);
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);

    await tester.tap(_inPalette('general'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-palette-input')), findsNothing);
    final context = tester.element(find.text('conversation').first);
    expect(GoRouterState.of(context).uri.path, '/channels/ch1');

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('arrow keys move the highlight and Enter runs it', (
    tester,
  ) async {
    final setup = _setup();
    await MessageStore(setup.db).upsertChannels(const [
      api.Channel(id: 'ch1', name: 'general', kind: 'text', createdAt: 0),
      api.Channel(id: 'ch2', name: 'random', kind: 'text', createdAt: 1),
    ]);
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);

    // Both channels are in the same, first group; one arrow-down from the
    // default top highlight ("general") moves it onto "random".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // flutter_test's own docs: a raw Enter key never reaches `onSubmitted`,
    // since on a real device the engine, not Flutter, turns it into one.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-palette-input')), findsNothing);
    final context = tester.element(find.text('conversation').first);
    expect(GoRouterState.of(context).uri.path, '/channels/ch2');

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('Escape closes the palette', (tester) async {
    final setup = _setup();
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);
    expect(find.byKey(const Key('command-palette-input')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('command-palette-input')), findsNothing);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('selecting a member opens a DM and closes the palette', (
    tester,
  ) async {
    final setup = _setup();
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);

    await tester.tap(_inPalette('Ren'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-palette-input')), findsNothing);
    final context = tester.element(find.text('conversation').first);
    expect(GoRouterState.of(context).uri.path, '/channels/dm-1');

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('selecting "Open settings" navigates to settings', (
    tester,
  ) async {
    final setup = _setup();
    await _pump(tester, setup.container);
    await _pressCtrlK(tester);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(find.text('settings-screen'), findsOneWidget);

    await _teardown(tester, setup.container, setup.db);
  });

  testWidgets('closing the palette restores focus to what held it before', (
    tester,
  ) async {
    final setup = _setup();
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    // openCommandPalette reads the current route, so even this isolated
    // harness needs a real GoRouter ancestor rather than a bare MaterialApp.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                TextField(focusNode: fieldFocus, autofocus: true),
                ElevatedButton(
                  onPressed: () => openCommandPalette(context),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: setup.container,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light, AppTokens.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue);

    await _teardown(tester, setup.container, setup.db);
  });
}
