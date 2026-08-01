// SPDX-License-Identifier: Apache-2.0
/// On a compact layout the context menu slides up as a bottom sheet, matching
/// every other modal in the app, rather than floating right under the thumb
/// that opened it. Wider layouts keep the floating follower unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/context_menu_region.dart';
import 'package:slimm_design_system/design_system.dart';

const Key _anchor = Key('anchor');

Future<void> _pump(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Center(
          child: ContextMenuRegion(
            itemsBuilder: (close) => [
              AppMenuItem(label: 'Report', onTap: close),
            ],
            child: const SizedBox(
              key: _anchor,
              width: 120,
              height: 40,
              child: Text('a member row'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a compact layout opens the menu as a bottom sheet', (
    tester,
  ) async {
    await _pump(tester, const Size(360, 800));

    await tester.longPress(find.byKey(_anchor));
    await tester.pumpAndSettle();

    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'a phone long-press should slide the menu up as a sheet',
    );
    expect(find.byType(CompositedTransformFollower), findsNothing);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('a wide layout keeps the floating follower', (tester) async {
    await _pump(tester, const Size(1000, 800));

    await tester.longPress(find.byKey(_anchor));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(CompositedTransformFollower), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });
}
