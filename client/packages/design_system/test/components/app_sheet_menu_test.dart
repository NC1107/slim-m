// SPDX-License-Identifier: Apache-2.0
/// [AppSheetMenu] is the body [showAppSheet] callers pass when their content
/// is a list of [AppMenuItem]s: [AppMenu]'s own floating card is right next
/// to a cursor and wrong nested inside a bottom sheet, which already draws
/// its own surface and drag handle.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

const Size _phone = Size(360, 800);
const Size _desktop = Size(1280, 900);

Future<void> _pump(WidgetTester tester, Size window, {double? width}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: AppSheetMenu(
          width: width ?? 250,
          children: [
            AppMenuItem(label: 'One', onTap: () {}),
            const AppMenuDivider(),
            AppMenuItem(label: 'Two', onTap: () {}),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('on a phone the row spans the full width, with no AppMenu card',
      (tester) async {
    await _pump(tester, _phone);

    expect(
      find.byType(AppMenu),
      findsNothing,
      reason: 'a bottom sheet already draws one surface; AppMenu would nest '
          'a second, bordered one inside it',
    );
    expect(
      tester.getSize(find.byType(AppMenuItem).first).width,
      _phone.width - AppSpacing.s8 * 2,
      reason: 'the fixed AppMenu width used to leave dead space either side',
    );
  });

  testWidgets('on a desktop window it renders the ordinary floating card',
      (tester) async {
    await _pump(tester, _desktop, width: 250);

    expect(find.byType(AppMenu), findsOneWidget);
    expect(tester.getSize(find.byType(AppMenu)).width, 250);
  });
}
