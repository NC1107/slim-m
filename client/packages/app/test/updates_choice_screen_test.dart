// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The question a new desktop account is asked once, at signup (decision
/// 0025). Either answer is an answer: both persist, so neither the splash
/// nor this screen asks again, and both carry on into the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/auto_update_preference.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_app/src/screens/updates_choice_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  InstallFormat format = InstallFormat.rpm,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWith(
        (ref) => SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: Routes.updatesChoice,
    routes: [
      GoRoute(
        path: Routes.updatesChoice,
        builder: (context, state) => UpdatesChoiceScreen(format: format),
      ),
      GoRoute(
        path: Routes.channels,
        builder: (context, state) => const Scaffold(body: Text('the app')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('turning it on is remembered and hands off into the app', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Turn on automatic updates'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(autoUpdateKey), isTrue);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('"Not now" is an answer too, so nothing asks again', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(autoUpdateKey),
      isFalse,
      reason: 'an unanswered question is what makes the splash ask again',
    );
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('an rpm install is told its system will ask for a password', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('dnf'), findsOneWidget);
    expect(find.textContaining('password'), findsOneWidget);
  });

  testWidgets('a format that cannot install one says so instead of promising '
      'it', (tester) async {
    await _pump(tester, format: InstallFormat.tarball);
    expect(find.textContaining('cannot replace itself'), findsOneWidget);
    expect(find.textContaining('password'), findsNothing);
  });

  testWidgets('the screen names where to change the answer later', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('Settings, under About'), findsOneWidget);
  });
}
