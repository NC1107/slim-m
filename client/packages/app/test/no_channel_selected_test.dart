// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// shell.md: this is the very first screen a fresh desktop sign-in lands
/// on, and it used to be a single small line of grey text with no icon and
/// no next step - noticeably less than the functionally identical
/// `ChannelStartHeader` gets. Confirms it now carries the same visual
/// weight and names the actual next step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, {required bool touch}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: AppTouchTargets(
        enabled: touch,
        child: const Scaffold(body: NoChannelSelected()),
      ),
    ),
  );
}

void main() {
  testWidgets('carries an icon and a heading, not just a bare line', (
    tester,
  ) async {
    await _pump(tester, touch: false);

    expect(find.byIcon(AppIcons.hash), findsOneWidget);
    expect(find.text('Pick a channel to start reading.'), findsOneWidget);
  });

  testWidgets('names the actual next step, keyboard-aware', (tester) async {
    await _pump(tester, touch: false);
    expect(find.textContaining('Ctrl+K'), findsOneWidget);

    await _pump(tester, touch: true);
    expect(find.textContaining('Ctrl+K'), findsNothing);
    expect(find.textContaining('Choose one from the list'), findsOneWidget);
  });
}
