// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `AppListRow`'s `meta` sits against the trailing edge, and a strong-label
/// scope lifts the label colour, both of which settings rows depend on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget row) => tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 600, child: row),
          ),
        ),
      ),
    );

void main() {
  testWidgets('meta sits against the trailing edge, not mid-row', (
    tester,
  ) async {
    await _pump(tester, const AppListRow(label: 'Theme', meta: 'System'));

    final row = tester.getRect(find.byType(AppListRow));
    final meta = tester.getRect(find.text('System'));
    expect(row.right - meta.right, lessThanOrEqualTo(AppSpacing.s8));
  });

  testWidgets('a long label keeps its width beside a short meta', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppListRow(label: 'Attachment preview quality', meta: 'Sharp'),
    );

    final size = tester.getSize(find.text('Attachment preview quality'));
    expect(size.width, greaterThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a strong-label scope reads the label in text-primary', (
    tester,
  ) async {
    Color? colorOf(WidgetTester t) =>
        t.widget<Text>(find.text('Theme')).style?.color;

    await _pump(tester, const AppListRow(label: 'Theme'));
    expect(colorOf(tester), AppTokens.light.textSecondary);

    await _pump(
      tester,
      const AppStrongLabelScope(child: AppListRow(label: 'Theme')),
    );
    expect(colorOf(tester), AppTokens.light.textPrimary);
  });
}
