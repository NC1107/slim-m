// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `AppInfoSection` used to render its Version and Debug log rows as bare
/// `ListTile`s, the taller, differently-inset row the design system's own
/// font-fix commit named as a defect (#477) but did not itself convert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/auto_update_preference.dart';
import 'package:slimm_app/src/widgets/app_info_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'settings_harness.dart';

void main() {
  setUpAll(mockAppVersion);

  testWidgets('the App group is AppListRow throughout, never a bare ListTile', (
    tester,
  ) async {
    await pumpPersonalSettings(tester, 0, scrollToBottom: false);

    await tester.tap(find.text('About slim-m'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Version'), findsOneWidget);
    expect(find.textContaining('0.1.0'), findsOneWidget);
    expect(find.text('Debug log'), findsOneWidget);
    expect(find.text('Nothing caught this session'), findsOneWidget);
  });

  /// Decision 0025: the switch that decides whether the splash installs an
  /// update on each launch lives here, because About is where the version it
  /// would change is already shown.
  testWidgets('automatic updates is a switch here, and moving it persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPersonalSettings(tester, 0, scrollToBottom: false);

    await tester.tap(find.text('About slim-m'));
    await tester.pumpAndSettle();

    expect(find.text('Automatic updates'), findsOneWidget);
    final toggle = find.byType(AppToggle);
    expect(
      tester.widget<AppToggle>(toggle).value,
      isFalse,
      reason: 'an install nobody has asked is not opted in',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      (await SharedPreferences.getInstance()).getBool(autoUpdateKey),
      isTrue,
    );
  });

  test('the switch says what it does for this install format', () {
    expect(
      automaticUpdatesDescription(InstallFormat.rpm),
      contains('package manager'),
    );
    expect(
      automaticUpdatesDescription(InstallFormat.tarball),
      contains('Tell me'),
    );
  });
}
