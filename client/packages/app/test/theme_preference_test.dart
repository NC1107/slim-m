// SPDX-License-Identifier: Apache-2.0
/// Tests for the appearance choice: it must actually drive the theme, it must
/// survive a restart, and an install with nothing stored must keep following
/// the operating system exactly as it did before there was a control at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/main.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/appearance_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// A container built the way `main()` builds one, so a second call to this
/// after a `select` is the same thing as relaunching the app.
ProviderContainer _restartedContainer() {
  final container = ProviderContainer(overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// The theme the app is really painting with, read from below MaterialApp
/// rather than from the provider, so a missing `themeMode:` cannot pass.
ThemeData _paintedTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

/// The section on its own, in the list that settings puts it in.
Future<void> _pumpSection(
    WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: ListView(children: const [AppearanceSettingsSection()]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The labels the section draws, spelled out here rather than imported: they
/// are the user-facing contract, so a rename should fail a test.
String _labelOf(AppThemeChoice choice) => switch (choice) {
      AppThemeChoice.system => 'System',
      AppThemeChoice.light => 'Light',
      AppThemeChoice.dark => 'Dark',
      AppThemeChoice.trueBlack => 'True black',
    };

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SlimMApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an install with nothing stored follows the system', () async {
    final container = _restartedContainer();
    await container.read(themeControllerProvider.notifier).restore();

    expect(container.read(themeControllerProvider), AppThemeChoice.system);
  });

  test('a stored value this build does not know falls back to the system',
      () async {
    SharedPreferences.setMockInitialValues({themeChoiceKey: 'solarized'});
    final container = _restartedContainer();
    await container.read(themeControllerProvider.notifier).restore();

    expect(container.read(themeControllerProvider), AppThemeChoice.system);
  });

  test('the choice survives a restart', () async {
    final first = _restartedContainer();
    await first.read(themeControllerProvider.notifier).restore();
    await first
        .read(themeControllerProvider.notifier)
        .select(AppThemeChoice.trueBlack);

    // A fresh container reads the same preference store, which is what a
    // relaunch does; nothing is carried over in memory.
    final second = _restartedContainer();
    expect(second.read(themeControllerProvider), AppThemeChoice.system);
    await second.read(themeControllerProvider.notifier).restore();

    expect(second.read(themeControllerProvider), AppThemeChoice.trueBlack);
  });

  testWidgets('the picker survives a list and a phone at a large text scale',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = _restartedContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            // A list is what settings is, and it gives its children no height
            // bound, which is the constraint the card variant needs one for.
            child: ListView(
              children: const [AppearanceSettingsSection()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('True black'), findsOneWidget);
  });

  testWidgets('tapping a segment is what actually changes the theme',
      (tester) async {
    final container = _restartedContainer();
    await container.read(themeControllerProvider.notifier).restore();
    await _pumpSection(tester, container);

    expect(container.read(themeControllerProvider), AppThemeChoice.system);

    await tester.tap(find.text('True black'));
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), AppThemeChoice.trueBlack,
        reason: 'the segment is the only control the user has for the whole '
            'theme feature; driving the controller directly proves nothing '
            'about whether it is wired to anything');
    expect(
      tester
          .widget<AppSegmentedControl>(find.byType(AppSegmentedControl))
          .selectedIndex,
      AppThemeChoice.values.indexOf(AppThemeChoice.trueBlack),
      reason: 'the control has to redraw on the choice it just reported',
    );

    // A relaunch reads the preference store, so this is the tap proving it
    // reached `select` rather than only setting state.
    final relaunched = _restartedContainer();
    await relaunched.read(themeControllerProvider.notifier).restore();
    expect(relaunched.read(themeControllerProvider), AppThemeChoice.trueBlack);
  });

  testWidgets('every appearance option is reachable by tapping it',
      (tester) async {
    for (final choice in AppThemeChoice.values) {
      SharedPreferences.setMockInitialValues({});
      final container = _restartedContainer();
      await container.read(themeControllerProvider.notifier).restore();
      container.read(themeControllerProvider.notifier).state =
          AppThemeChoice.light;
      await _pumpSection(tester, container);

      await tester.tap(find.text(_labelOf(choice)));
      await tester.pumpAndSettle();

      expect(container.read(themeControllerProvider), choice,
          reason: 'tapping ${_labelOf(choice)} must select it');
    }
  });

  testWidgets('a chosen light theme wins over a dark operating system',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final container = _restartedContainer();
    container.read(themeControllerProvider.notifier).state =
        AppThemeChoice.light;
    await _pumpApp(tester, container);

    expect(_paintedTheme(tester).brightness, Brightness.light);
  });

  testWidgets('a chosen dark theme wins over a light operating system',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final container = _restartedContainer();
    container.read(themeControllerProvider.notifier).state =
        AppThemeChoice.dark;
    await _pumpApp(tester, container);

    final theme = _paintedTheme(tester);
    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<AppTokens>(), AppTokens.dark);
  });

  testWidgets('true black is reachable, and following the system never is',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final container = _restartedContainer();
    container.read(themeControllerProvider.notifier).state =
        AppThemeChoice.trueBlack;
    await _pumpApp(tester, container);

    expect(
      _paintedTheme(tester).extension<AppTokens>()!.surfaceBase,
      const Color(0xFF000000),
    );

    container.read(themeControllerProvider.notifier).state =
        AppThemeChoice.system;
    await tester.pumpAndSettle();

    // On a dark system this is dark, but it is the ordinary dark palette:
    // true black is an OLED decision no operating system reports.
    expect(_paintedTheme(tester).extension<AppTokens>(), AppTokens.dark);
  });
}
