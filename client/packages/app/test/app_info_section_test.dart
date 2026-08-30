// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `AppInfoSection` used to render its Version and Debug log rows as bare
/// `ListTile`s, the taller, differently-inset row the design system's own
/// font-fix commit named as a defect (#477) but did not itself convert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
