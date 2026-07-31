// SPDX-License-Identifier: Apache-2.0
/// Tests for the composer's key handling while a `:`/`@`/`/` suggestion list
/// is open.
///
/// The defect this pins: the accept branch bailed on Shift alone, so
/// Ctrl+Tab (the next-channel shortcut) accepted whatever suggestion was
/// highlighted and swallowed the key instead of ever reaching the shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'composer_harness.dart';

void main() {
  late TextEditingController controller;
  late Sends sends;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = TextEditingController();
    sends = Sends();
  });

  tearDown(() => controller.dispose());

  Future<void> openSuggestion(WidgetTester tester) async {
    await tester.pumpWidget(
      composerHarness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.linux,
        customEmoji: [custom('party_parrot')],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), ':party');
    await tester.pump();
    expect(find.text(':party_parrot:'), findsOneWidget);
  }

  testWidgets('a plain Tab accepts the highlighted suggestion', (tester) async {
    await openSuggestion(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, ':party_parrot: ');
    expect(find.text(':party_parrot:'), findsNothing);
  });

  testWidgets('Ctrl+Tab leaves the suggestion open for the shell to cycle '
      'channels instead', (tester) async {
    await openSuggestion(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, ':party');
    expect(find.text(':party_parrot:'), findsOneWidget);
  });

  testWidgets('Ctrl+Shift+Tab leaves the suggestion open too', (tester) async {
    await openSuggestion(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, ':party');
    expect(find.text(':party_parrot:'), findsOneWidget);
  });
}
