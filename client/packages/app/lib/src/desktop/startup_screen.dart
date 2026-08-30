// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Discord-style startup screen: the brand lockup plus a status line,
/// shown in its own small window while `main.dart`'s async bootstrap
/// sequence runs, per decision 0012's superseding section.
///
/// A real, small OS window now, not a themed first frame inside the one
/// real window the way this screen first shipped - the owner reaffirmed the
/// ask decision 0012 originally rejected, with a use case that record never
/// weighed: this splash is meant to eventually host update-check/download
/// progress, which must exist before and outlive the main window's first
/// frame. See `DesktopWindowShell.applyInitialGeometry`, called ahead of
/// `runApp`, which is what actually puts the window into this small,
/// frameless, centred, fixed-size splash shape; this widget only draws what
/// sits inside it.
///
/// [status] is the room for that future update text: "Checking for
/// updates", "Downloading update", "Installing update" are the same one
/// line this already shows during ordinary bootstrap, just with different
/// words - see `main.dart`'s `startupStatusProvider` for where the current,
/// simple phase text comes from.
///
/// The mark alone, at the size `BootSplashScreen` uses for a phone, read as
/// an accidental placeholder rather than a designed screen once it sat in a
/// full desktop window rather than a phone's - the owner's own "looks
/// buggy" report. Pairing it with the wordmark `OnboardingShell`'s brand
/// rail already carries gives the same content the weight a splash needs to
/// read as deliberate, without inventing a new visual language for one
/// screen.
///
/// Always dark, regardless of the stored theme choice: that choice is
/// itself part of the async sequence this screen exists to mask, so there
/// is nothing else to render it in yet. Discord's own splash does the same.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// The default [StartupScreen.status] text, and the only one every existing
/// test and every non-desktop launch ever sees: `main.dart` overrides it
/// with `startupStatusProvider`'s live value once bootstrap actually starts.
const defaultStartupStatus = 'Starting slim-m';

class StartupApp extends StatelessWidget {
  const StartupApp({super.key, this.status = defaultStartupStatus});

  final String status;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'slim-m',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: StartupScreen(status: status),
  );
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, this.status = defaultStartupStatus});

  final String status;

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
              const SizedBox(height: AppSpacing.s24),
              Text(
                status,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
