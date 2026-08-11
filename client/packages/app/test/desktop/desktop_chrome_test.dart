// SPDX-License-Identifier: Apache-2.0
/// [DesktopChrome] must pass its child through completely unwrapped while
/// [DesktopWindowShell.active] is false - the property every other widget
/// test in this package's tree shape depends on never changing, since
/// `flutter test` genuinely runs on Linux and nothing else distinguishes a
/// test run from a real desktop launch until the shell actually starts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/desktop_chrome.dart';
import 'package:slimm_app/src/desktop/desktop_window_shell.dart';

void main() {
  testWidgets(
    'passes the child straight through when the shell was never started',
    (tester) async {
      expect(
        DesktopWindowShell.active,
        isFalse,
        reason: 'nothing in this test run ever calls registerListenersAndTray',
      );

      await tester.pumpWidget(
        const MaterialApp(home: DesktopChrome(child: Text('real content'))),
      );

      expect(find.text('real content'), findsOneWidget);
      // Exactly what was handed in - no ProviderScope required either.
      expect(find.byType(Column), findsNothing);
    },
  );
}
