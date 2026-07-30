// SPDX-License-Identifier: Apache-2.0
/// The ThemeData built from a token set.
///
/// Split from `app_tokens.dart` when the component themes pushed that file
/// past the 500-line ceiling; the tokens stay a value catalogue and this is
/// the one place they compile into Material.
library;

import 'package:flutter/material.dart';

import 'app_metrics.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds a theme from the token set, so widgets read colours from tokens and
/// never from raw literals. Shared by the app and the golden tests, which is
/// what keeps goldens representative of what ships.
///
/// The component themes below are what keep a raw Material widget on the
/// system when it slips past the `App*` components: without them a bare
/// `FilledButton` is a Material stadium pill and a bare `TextField` an
/// underline, which is exactly how the production review found every screen
/// drifting toward default Material. Buttons take the control radius (6, not
/// full), inputs take the hairline box `AppInput` draws, and the text theme
/// carries this system's scale, whose heaviest weight is 600 by rule.
///
/// Both accent roles are pinned to their tokens rather than left to
/// `fromSeed`, for one reason: Material derives its own tone from the seed,
/// and a derived tone is a different colour from the hand-picked token even
/// when the seed *is* that token. `error` was pinned an audit round ago after
/// two reds meaning "danger" turned up across the app. `primary` was left out
/// and had the same effect on every raw `FilledButton`, `TextButton` and
/// `OutlinedButton`, so the front door's button and the wordmark beside it
/// were measurably two different accents. Pinning both makes any raw
/// `colorScheme.primary` or `.error` correct by construction rather than by
/// every call site remembering.
ThemeData buildTheme(Brightness brightness, AppTokens tokens) {
  // Overridden, never left to fromSeed; see this function's own doc comment.
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accentFill,
    brightness: brightness,
  ).copyWith(
    surface: tokens.surfaceBase,
    primary: tokens.accentFill,
    onPrimary: tokens.accentOn,
    error: tokens.dangerText,
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
  );
  // The family is named explicitly: a button theme's textStyle replaces the
  // inherited style wholesale, so without it every Material button silently
  // fell back to the platform default face.
  final buttonLabel = AppText.ui.copyWith(
    fontWeight: AppWeights.semi,
    fontFamily: AppFonts.sans,
    fontFamilyFallback: AppFonts.emoji,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surfaceBase,
    fontFamily: AppFonts.sans,
    fontFamilyFallback: AppFonts.emoji,
    extensions: [tokens],
    dividerTheme: DividerThemeData(color: tokens.borderSubtle, space: 1),
    textTheme: TextTheme(
      headlineSmall: AppText.title.copyWith(color: tokens.textPrimary),
      titleLarge: AppText.heading.copyWith(
        color: tokens.textPrimary,
        fontWeight: AppWeights.semi,
      ),
      titleMedium: AppText.body.copyWith(
        color: tokens.textPrimary,
        fontWeight: AppWeights.medium,
      ),
      titleSmall: AppText.ui.copyWith(
        color: tokens.textPrimary,
        fontWeight: AppWeights.medium,
      ),
      bodyLarge: AppText.body.copyWith(color: tokens.textPrimary),
      bodyMedium: AppText.ui.copyWith(color: tokens.textPrimary),
      bodySmall: AppText.caption.copyWith(color: tokens.textSecondary),
      labelLarge: buttonLabel,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surfaceBase,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.heading.copyWith(
        color: tokens.textPrimary,
        fontWeight: AppWeights.semi,
        fontFamily: AppFonts.sans,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: controlShape).copyWith(
        textStyle: WidgetStatePropertyAll(buttonLabel),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: controlShape).copyWith(
        textStyle: WidgetStatePropertyAll(buttonLabel),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: controlShape).copyWith(
        textStyle: WidgetStatePropertyAll(buttonLabel),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: controlShape).copyWith(
        textStyle: WidgetStatePropertyAll(buttonLabel),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: tokens.focusRing, width: 2),
      ),
      // A failing field is marked on the field itself (error grammar 03):
      // red hairline, red caption, content preserved. The button never
      // turns red - the field failed, not the button.
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: tokens.dangerBorder),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: tokens.dangerBorder, width: 2),
      ),
      errorStyle: AppText.caption.copyWith(color: tokens.dangerText),
      labelStyle: AppText.body.copyWith(color: tokens.textSecondary),
      floatingLabelStyle: AppText.caption.copyWith(color: tokens.textSecondary),
      hintStyle: AppText.body.copyWith(color: tokens.textDisabled),
      helperStyle: AppText.caption.copyWith(color: tokens.textSecondary),
    ),
    // Raw ListTiles took M3's onSurface, putting two blacks in one panel.
    listTileTheme: ListTileThemeData(
      textColor: tokens.textPrimary,
      iconColor: tokens.textSecondary,
      titleTextStyle: AppText.body.copyWith(color: tokens.textPrimary),
      subtitleTextStyle: AppText.caption.copyWith(color: tokens.textSecondary),
    ),
  );
}
