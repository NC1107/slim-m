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
/// The mark alone, at the size [BootSplashScreen] uses for a phone, read as
/// an accidental placeholder rather than a designed screen once it sat in a
/// full desktop window rather than a phone's - the owner's own "looks
/// buggy" report. Pairing it with the wordmark `OnboardingShell`'s brand
/// rail already carries gives the same content the weight a full-window
/// splash needs to read as deliberate, without inventing a new visual
/// language for one screen.
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBrandMark(size: 64, color: tokens.accent),
              const SizedBox(height: AppSpacing.s16),
              Text(
                'slim-m',
                style: AppText.heading.copyWith(
                  color: tokens.textPrimary,
                  fontFamily: AppFonts.mono,
                  fontWeight: AppWeights.medium,
                  letterSpacing: 20 * AppTracking.mono,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
