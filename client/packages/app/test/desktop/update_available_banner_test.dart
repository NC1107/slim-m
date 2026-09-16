// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [UpdateAvailableBanner] itself: it renders nothing until a session check
/// finds something, names the version, and dismissing it both hides it and
/// writes the same dismissal the splash's own "Not now" uses.
///
/// [inSessionUpdateProvider] is overridden directly rather than driven
/// through a real [UpdateWatcher]: this file is only about what the banner
/// does with a find, not how one arrives - `update_watch_test.dart` covers
/// the timer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/update_available_banner.dart';
import 'package:slimm_app/src/desktop/update_check.dart';
import 'package:slimm_app/src/desktop/update_watch.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _update = ClientUpdate(
  version: '9.9.9',
  releaseUrl: 'https://example.invalid/release',
  format: InstallFormat.tarball,
);

Future<void> _pump(WidgetTester tester, ClientUpdate? update) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inSessionUpdateProvider.overrideWith((ref) => update),
        // No real Timer here: this file is about the banner, not the poll.
        updateWatcherProvider.overrideWith(
          (ref) => UpdateWatcher(ref, shouldRun: () => false),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: UpdateAvailableBanner()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders nothing while no update has been found', (tester) async {
    await _pump(tester, null);

    expect(find.byType(AppCallout), findsNothing);
  });

  testWidgets('names the version once one is found', (tester) async {
    await _pump(tester, _update);

    expect(find.byType(AppCallout), findsOneWidget);
    expect(find.textContaining('9.9.9'), findsOneWidget);
    expect(find.textContaining('Restart'), findsOneWidget);
  });

  testWidgets(
    'dismissing hides the banner and records the same dismissal the splash '
    'reads',
    (tester) async {
      await _pump(tester, _update);
      expect(find.byType(AppCallout), findsOneWidget);

      await tester.tap(find.byType(AppIconButton));
      await tester.pump();
      await tester.pump();

      expect(find.byType(AppCallout), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(dismissedUpdateVersionKey), '9.9.9');
    },
  );
}
