// SPDX-License-Identifier: Apache-2.0
/// [WindowMenuButton] is the guaranteed quit control this pane exists to
/// close a real gap for: on a desktop with no tray host, the tray menu's
/// own "Quit slim-m" item never renders anywhere, so this has to be its own
/// reachable route, by mouse and by keyboard both.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/window_menu_button.dart';
import 'package:slimm_design_system/design_system.dart';

import 'support/fake_desktop_window_port.dart';

Future<SemanticsHandle> _pump(
  WidgetTester tester,
  FakeDesktopWindowPort port,
) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: WindowMenuButton(port: port),
        ),
      ),
    ),
  );
  return handle;
}

void main() {
  testWidgets('opens on tap and offers Quit slim-m', (tester) async {
    final handle = await _pump(tester, FakeDesktopWindowPort());

    expect(find.text('Quit slim-m'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Window menu'));
    await tester.pumpAndSettle();
    expect(find.text('Quit slim-m'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('tapping Quit slim-m calls destroy on the port exactly once', (
    tester,
  ) async {
    final port = FakeDesktopWindowPort();
    final handle = await _pump(tester, port);

    await tester.tap(find.bySemanticsLabel('Window menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quit slim-m'));
    await tester.pumpAndSettle();

    expect(port.destroyCalls, 1);
    handle.dispose();
  });

  testWidgets('Escape closes the menu without quitting', (tester) async {
    final port = FakeDesktopWindowPort();
    final handle = await _pump(tester, port);

    await tester.tap(find.bySemanticsLabel('Window menu'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Quit slim-m'), findsNothing);
    expect(port.destroyCalls, 0);
    handle.dispose();
  });

  testWidgets(
    'the trigger and the open menu item are both real, focusable buttons '
    'in the actual dumped semantics tree, not merely painted to look like '
    'one',
    (tester) async {
      final handle = await _pump(tester, FakeDesktopWindowPort());

      final trigger = tester.getSemantics(find.bySemanticsLabel('Window menu'));
      final triggerData = trigger.getSemanticsData();
      expect(triggerData.flagsCollection.isButton, isTrue);
      expect(triggerData.flagsCollection.isFocused, isNot(Tristate.none));
      expect(triggerData.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.bySemanticsLabel('Window menu'));
      await tester.pumpAndSettle();

      final owner = tester
          .binding
          // ignore: deprecated_member_use
          .pipelineOwner;
      final dump = owner.semanticsOwner!.rootSemanticsNode!.toStringDeep();
      expect(dump, contains('Quit slim-m'));

      final quitItem = tester.getSemantics(find.byType(AppMenuItem));
      final quitItemData = quitItem.getSemanticsData();
      expect(quitItemData.flagsCollection.isButton, isTrue);
      expect(quitItemData.flagsCollection.isFocused, isNot(Tristate.none));
      expect(quitItemData.hasAction(SemanticsAction.tap), isTrue);

      handle.dispose();
    },
  );
}
