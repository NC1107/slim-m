// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

/// Semantic design tokens for slim-m, exposed as a [ThemeExtension] so a widget
/// does one lookup (`Theme.of(context).extension<AppTokens>()`).
///
/// Values are provisional: the accent and border colors are gated by an
/// automated WCAG 2.1 AA contrast check before they are locked, and a designer
/// review precedes the final palette. Do not hardcode these hex values in
/// widgets; read them through this extension.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
  });

  final Color surfaceBase;
  final Color surfaceRaised;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;

  /// Cool-slate light theme with one restrained teal accent.
  static const AppTokens light = AppTokens(
    surfaceBase: Color(0xFFF7F8F9),
    surfaceRaised: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFDCE0E5),
    textPrimary: Color(0xFF1B1E22),
    textSecondary: Color(0xFF5B6169),
    accent: Color(0xFF1E7F77),
  );

  /// Hand-tuned dark theme (not a mechanical inversion of light).
  static const AppTokens dark = AppTokens(
    surfaceBase: Color(0xFF17191C),
    surfaceRaised: Color(0xFF1F2226),
    borderSubtle: Color(0xFF2E333A),
    textPrimary: Color(0xFFECEDEF),
    textSecondary: Color(0xFFA7AEB6),
    accent: Color(0xFF4FBDB4),
  );

  @override
  AppTokens copyWith({
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
  }) {
    return AppTokens(
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

/// The 4dp spacing grid, named by value.
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
}

/// Corner radii; elevation is border-first, so shadows are rare.
abstract final class AppRadii {
  static const double chip = 4;
  static const double control = 6;
  static const double card = 10;
  static const double window = 16;
}

/// Builds a theme from the token set, so widgets read colours from tokens and
/// never from raw literals. Shared by the app and the golden tests, which is
/// what keeps goldens representative of what ships.
ThemeData buildTheme(Brightness brightness, AppTokens tokens) {
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accent,
    brightness: brightness,
  ).copyWith(surface: tokens.surfaceBase);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surfaceBase,
    extensions: [tokens],
    dividerTheme: DividerThemeData(color: tokens.borderSubtle, space: 1),
  );
}
