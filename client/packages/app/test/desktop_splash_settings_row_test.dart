// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The desktop splash toggle and duration row inside the performance pane:
/// turning the splash off both persists and hides the duration row (nothing
/// to time once the splash never shows), turning it back on both persists and
/// restores the row, and picking a duration persists that choice.
///
/// A new preference gets its own file rather than growing
/// `performance_settings_section_test.dart` again - the same shape
/// `voice_settings_push_to_talk_test.dart` already uses. The explicit desktop
/// width matches `settings_select_row_test.dart`'s own harness: the row's
/// choices drop down anchored to it only at or above `kCompactWidth`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/desktop_splash_preference.dart';
import 'package:slimm_app/src/widgets/performance_settings_section.dart';
import 'package:slimm_app/src/widgets/settings_select_row.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _wrap() => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const Scaffold(
      body: SingleChildScrollView(child: PerformanceSettingsSection()),
    ),
  ),
);

Finder _splashToggle() => find.byWidgetPredicate(
  (w) => w is AppToggle && w.semanticLabel == 'Startup splash',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the splash is on and the duration row shows by default', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(_splashToggle(), findsOneWidget);
    expect(find.text('Splash duration'), findsOneWidget);
    expect(find.text('Standard (default)'), findsOneWidget);
  });

  testWidgets('turning the splash off persists it and hides the duration '
      'row', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(_splashToggle());
    await tester.pumpAndSettle();

    expect(find.text('Splash duration'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(desktopSplashEnabledKey), isFalse);
  });

  testWidgets('turning the splash back on persists it and restores the '
      'duration row', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The tree never calls restore() itself, so off-then-on exercises "back on" here.
    await tester.tap(_splashToggle());
    await tester.pumpAndSettle();
    expect(find.text('Splash duration'), findsNothing);

    await tester.tap(_splashToggle());
    await tester.pumpAndSettle();

    expect(find.text('Splash duration'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(desktopSplashEnabledKey), isTrue);
  });

  testWidgets('picking Long persists that choice', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SettingsSelectRow<SplashDuration>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long'));
    await tester.pumpAndSettle();

    expect(find.text('Long'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(desktopSplashDurationKey), 'long');
  });
}
