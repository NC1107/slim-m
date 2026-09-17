// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [UpdateBannerHost], the reason a phone sees the update banner at all.
///
/// The banner's own file is mounted in `DesktopChrome`, outside the router,
/// so before this wrapper existed a mobile build polled for nothing: no
/// surface ever read [inSessionUpdateProvider]. These tests are about the
/// mounting decision rather than the banner's content, which
/// `desktop/update_available_banner_test.dart` covers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/update_check.dart';
import 'package:slimm_app/src/desktop/update_watch.dart';
import 'package:slimm_app/src/widgets/update_banner_host.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _update = ClientUpdate(
  version: '9.9.9',
  releaseUrl: 'https://example.invalid/release',
  format: InstallFormat.unknown,
);

Future<void> _pump(
  WidgetTester tester, {
  required bool ownsBanner,
  ClientUpdate? update,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inSessionUpdateProvider.overrideWith((ref) => update),
        // No real Timer: this file is about where the banner mounts.
        updateWatcherProvider.overrideWith(
          (ref) => UpdateWatcher(ref, shouldRun: () => false),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: UpdateBannerHost(
          ownsBanner: ownsBanner,
          child: const Scaffold(body: Text('the app')),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a layout with no outer chrome shows the banner itself', (
    tester,
  ) async {
    await _pump(tester, ownsBanner: false, update: _update);

    expect(find.byType(AppCallout), findsOneWidget);
    expect(find.textContaining('9.9.9'), findsOneWidget);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('desktop chrome already has one, so this mounts no second', (
    tester,
  ) async {
    await _pump(tester, ownsBanner: true, update: _update);

    expect(
      find.byType(AppCallout),
      findsNothing,
      reason:
          'DesktopChrome mounts the banner outside the router; two banners '
          'saying the same thing is worse than none',
    );
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('costs nothing but the child while no update has been found', (
    tester,
  ) async {
    await _pump(tester, ownsBanner: false);

    expect(find.byType(AppCallout), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });
}
