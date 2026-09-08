// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A sheet's pinned parts keep their own semantics nodes.
///
/// A dialog route names itself from every descendant that forms no node of its
/// own. Content inside a scroll region is safe, since the scrollable is a
/// boundary, but a heading or an action button pinned *beside* the scroll
/// region (the layout `scrolls: true` exists for) was merged into the route's
/// label and lost its tap action - a screen reader could not reach "Create
/// role", and neither could the e2e harness, which drives the app through the
/// same tree. `showAppSheet` now wraps its content the way `AlertDialog` wraps
/// its own, so both branches are pinned here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _pinnedForm() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('New role'),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 40, child: Text('Row $i')),
              ],
            ),
          ),
        ),
        AppButton(
          label: 'Create role',
          variant: AppButtonVariant.primary,
          onPressed: () {},
        ),
      ],
    );

Future<void> _open(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                scrolls: true,
                builder: (_) => _pinnedForm(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, width) in [('dialog', 1200.0), ('bottom sheet', 400.0)]) {
    testWidgets(
        'a heading and action pinned beside the scroll region are '
        'their own nodes in the $name branch', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, width);

      expect(find.bySemanticsLabel('New role'), findsOneWidget);
      final button = find.bySemanticsLabel('Create role');
      expect(button, findsOneWidget);
      expect(
        tester
            .getSemantics(button)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'a button swallowed into the route label loses its tap',
      );
      handle.dispose();
    });
  }
}
