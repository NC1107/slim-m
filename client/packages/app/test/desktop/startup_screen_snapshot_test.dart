// SPDX-License-Identifier: Apache-2.0
/// A real render of [StartupScreen] at the one size it now actually launches
/// into: [DesktopWindowShell.splashWindowSize], the small splash window
/// decision 0012's superseding section describes - so a change here can be
/// looked at rather than guessed about. This screen no longer renders inside
/// the full desktop window (that was the pre-superseding design this file
/// used to snapshot at 1280x720 and 1920x1080): the splash is now a fixed
/// small size regardless of the real window's own saved geometry, so there
/// is exactly one size to check, plus a longer status string to confirm the
/// line this record adds room for does not overflow that small window.
///
/// Rendered through `flutter test`'s software rasteriser, never a real
/// window - the same "no display involved" category decision 0012 itself
/// names as safe to automate, unlike raising the built binary on this
/// machine's own display.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/desktop_window_shell.dart';
import 'package:slimm_app/src/desktop/startup_screen.dart';

import '../ui_snapshot_support.dart';

void main() {
  setUpAll(loadRealFonts);

  final splashSize = Size(
    DesktopWindowShell.splashWindowSize.width,
    DesktopWindowShell.splashWindowSize.height,
  );

  for (final entry in {
    'startup-screen-splash': const StartupApp(),
    'startup-screen-splash-update-status': const StartupApp(
      status: 'Downloading update',
    ),
  }.entries) {
    testWidgets('startup screen at ${entry.key}', (tester) async {
      tester.view.physicalSize = splashSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(key: snapshotBoundary, child: entry.value),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await writeSnapshot(tester, entry.key);
      expect(tester.takeException(), isNull);
    });
  }
}
