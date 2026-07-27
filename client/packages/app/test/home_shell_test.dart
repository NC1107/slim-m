// SPDX-License-Identifier: Apache-2.0
/// Tests for the shell's width-driven layout: the member pane must not
/// merely be styled as hidden, it must not be built at all below expanded
/// width, and must appear once the window is wide enough.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_app/src/widgets/member_pane.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// A container wired like the app's, with the network swapped for an
/// always-failing client (every provider that reads it already degrades to
/// an honest loading/error state rather than crashing) and the database
/// swapped for an in-memory one this test closes itself, on the same clock
/// the test binding uses; see [_teardown] for why that matters.
({ProviderContainer container, SlimmDatabase db}) _setup() {
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient(
            (_) async => throw StateError('no network in this test'),
          ),
        );
        ref.onDispose(api.close);
        return api;
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
/// unconditionally shows [HomeShell].
GoRouter _testRouter() => GoRouter(
  initialLocation: '/channels',
  routes: [
    GoRoute(
      path: '/channels',
      builder: (context, state) =>
          const HomeShell(child: Center(child: Text('conversation'))),
    ),
  ],
);

Future<void> _pumpAtWidth(
  WidgetTester tester,
  ProviderContainer container,
  double width,
) async {
  tester.view.physicalSize = Size(width, 900);
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
}
