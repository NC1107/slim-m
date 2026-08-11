// SPDX-License-Identifier: Apache-2.0
/// The Discord-style startup screen: a small themed mark shown while
/// `main.dart`'s async bootstrap sequence runs, per decision 0012.
///
/// Deliberately not a second OS window - the record rejects that option by
/// name (a second top-level window is a second taskbar entry that flickers
/// in and out, and Wayland gives an app no way to place it relative to
/// where the real window will land). Geometry is applied before the very
/// first frame paints (see `DesktopWindowShell.applyInitialGeometry`,
/// called ahead of `runApp`), so this screen already renders inside a
/// window already sized to its last known bounds - nothing resizes visibly
/// when the real UI swaps in.
///
/// Always dark, regardless of the stored theme choice: that choice is
/// itself part of the async sequence this screen exists to mask, so there
/// is nothing else to render it in yet. Discord's own splash does the same.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class StartupApp extends StatelessWidget {
  const StartupApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'slim-m',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: const StartupScreen(),
  );
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.dark;
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: Center(
        child: AppFadeIn(
          offset: 0,
          child: AppBrandMark(size: 56, color: tokens.accent),
        ),
      ),
    );
  }
}
