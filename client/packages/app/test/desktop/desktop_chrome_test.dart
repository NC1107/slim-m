// SPDX-License-Identifier: Apache-2.0
/// [DesktopChrome] must pass its child through completely unwrapped while
/// [DesktopWindowShell.active] is false - the property every other widget
/// test in this package's tree shape depends on never changing, since
/// `flutter test` genuinely runs on Linux and nothing else distinguishes a
/// test run from a real desktop launch until the shell actually starts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/desktop_chrome.dart';
import 'package:slimm_app/src/desktop/desktop_window_shell.dart';
import 'package:slimm_design_system/design_system.dart';

import 'support/fake_desktop_window_port.dart';

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

  testWidgets(
    'active chrome gives its text a real style, not the fallback underline',
    (tester) async {
      // The real placement: chrome in MaterialApp's builder, no Scaffold, so it must carry its own Material or the text inherits the fallback underline.
      DesktopWindowShell.debugPort = FakeDesktopWindowPort();
      DesktopWindowShell.debugActivate(frameless: true);
      addTearDown(DesktopWindowShell.debugReset);
      tester.view.physicalSize = const Size(1400, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(Brightness.dark, AppTokens.dark),
            builder: (context, child) => DesktopChrome(child: child!),
            home: const SizedBox.expand(),
          ),
        ),
      );

      final style = DefaultTextStyle.of(
        tester.element(find.text('slim-m')),
      ).style;
      expect(
        style.decoration,
        isNot(TextDecoration.underline),
        reason: 'chrome text inherited the fallback underline: no Material',
      );
      expect(DesktopChrome, isNotNull);
      expect(find.byType(Material), findsWidgets);
    },
  );

  testWidgets("the title bar's window menu opens - the chrome carries an Overlay", (
    tester,
  ) async {
    // The window menu is an OverlayPortal; without the chrome's own Overlay it threw "No Overlay widget found" and never opened.
    DesktopWindowShell.debugPort = FakeDesktopWindowPort();
    DesktopWindowShell.debugActivate(frameless: true);
    addTearDown(DesktopWindowShell.debugReset);
    tester.view.physicalSize = const Size(1400, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, AppTokens.dark),
          builder: (context, child) => DesktopChrome(child: child!),
          home: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tap(find.byIcon(AppIcons.moreVertical), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Quit slim-m'), findsOneWidget);
    // The menu sizes to its content, not the window: a full-width band was the no-overlay symptom.
    final menu = tester.getSize(
      find
          .ancestor(
            of: find.text('Quit slim-m'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(menu.width, lessThan(300));
  });
}
