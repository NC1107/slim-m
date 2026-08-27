// SPDX-License-Identifier: Apache-2.0
/// A real render of [StartupScreen] at the sizes it actually launches into:
/// [WindowGeometry.fallback]'s cold-start default, and a larger restored
/// window, so a change here can be looked at rather than guessed about - the
/// owner's own complaint (`docs/decisions/0012-desktop-window-shell.md`) was
/// that the small mark alone read as a glitch stretched across a full
/// desktop window, which no widget test asserting the mark merely exists
/// would have caught.
///
/// Rendered through `flutter test`'s software rasteriser, never a real
/// window - the same "no display involved" category decision 0012 itself
/// names as safe to automate, unlike raising the built binary on this
/// machine's own display.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/startup_screen.dart';

import '../ui_snapshot_support.dart';

void main() {
  setUpAll(loadRealFonts);

  for (final entry in const {
    'startup-screen-cold-default': Size(1280, 720),
    'startup-screen-large-desktop': Size(1920, 1080),
  }.entries) {
    testWidgets('startup screen at ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(key: snapshotBoundary, child: const StartupApp()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await writeSnapshot(tester, entry.key);
      expect(tester.takeException(), isNull);
    });
  }
}
