// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

/// Semantic design tokens for slim-m, exposed as a [ThemeExtension] so a widget
/// does one lookup (`Theme.of(context).extension<AppTokens>()`).
///
/// Shaped by the 2026-07-26 visual identity review (see
/// `docs/decisions/0004-visual-identity-review.md`). Three things it changed
/// that are worth knowing before editing this file:
///
/// - **One accent token could not do two jobs.** A value legible as text and a
///   value recognisable as a fill are different colours, which is why light and
///   dark did not read as the same brand. The roles are split now, and the
///   contrast gate checks honest pairs instead of forcing one value through
///   both.
/// - **On true black the border is the whole elevation system.** Dark mode can
///   lean on fill difference; `#000000` cannot, so the hairline carries it
///   alone and had to be raised.
/// - **The accent is rare on purpose.** Seven roles, listed in the decision
///   record, and that list is closed. The failure mode is not a wrong hue, it
///   is the next contributor adding an accent border to something that looked
///   plain.
///
/// The accent hue itself is still open: the review recommends moving to a
/// glacier cyan because the shipped teal sits ~25 degrees from the online-status
/// green and competes with it in the member list. That is one primitive change
/// when it is decided. Do not hardcode any of these values in widgets.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surfaceSunken,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentFill,
    required this.accentOn,
    required this.accentSoft,
    required this.focusRing,
    required this.code,
  });

  /// A step below [surfaceBase], for the rails. Six surfaces were not enough to
  /// draw the shell without the panes bleeding into each other.
  final Color surfaceSunken;
  final Color surfaceBase;
  final Color surfaceRaised;

  /// The default separator. Elevation is border-first, so this does the work
  /// shadows do elsewhere.
  final Color borderSubtle;

  final Color textPrimary;
  final Color textSecondary;

  /// The accent as *text or icon*: contrast-bound, so it is darker in light
  /// mode and does not match [accentFill]'s hue exactly. Use for accented
  /// labels and glyphs on an ordinary surface.
  final Color accent;

  /// The accent as a *fill*: brand-true and the same hue in every theme, always
  /// paired with [accentOn] for whatever sits on top of it. Use for the one
  /// filled button per screen.
  final Color accentFill;

  /// What is legible on top of [accentFill].
  final Color accentOn;

  /// A ~12% tint of the accent, which does most of the actual accent work:
  /// selected rows, active channel background, operator chips.
  final Color accentSoft;

  /// The keyboard focus indicator. Deliberately its own token rather than the
  /// accent border used for active and selected states: if focus and selection
  /// look the same, a keyboard user cannot tell where they are.
  final Color focusRing;

  /// Syntax colours for fenced code blocks.
  final AppCodeColors code;

  /// Cool-slate light theme.
  static const AppTokens light = AppTokens(
    surfaceSunken: Color(0xFFEFF1F3),
    surfaceBase: Color(0xFFF7F8F9),
    surfaceRaised: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFDCE0E5),
    textPrimary: Color(0xFF1B1E22),
    textSecondary: Color(0xFF5B6169),
    // Darkened from #1E7F77 by the identity review's own consequence: adding
    // surface.sunken gave the accent a third surface to be legible on, and the
    // old value cleared base at 4.53:1 but only reached 4.26:1 on sunken. The
    // rails are sunken and do carry accent (active channel marker, unread
    // badge), so that combination is real rather than theoretical.
    accent: Color(0xFF1D7A72),
    accentFill: Color(0xFF1D7A72),
    accentOn: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFDDEEEC),
    focusRing: Color(0xFF1D7A72),
    code: AppCodeColors.light,
  );

  /// Hand-tuned dark theme (not a mechanical inversion of light).
  static const AppTokens dark = AppTokens(
    surfaceSunken: Color(0xFF131518),
    surfaceBase: Color(0xFF17191C),
    surfaceRaised: Color(0xFF1F2226),
    borderSubtle: Color(0xFF2E333A),
    textPrimary: Color(0xFFECEDEF),
    textSecondary: Color(0xFFA7AEB6),
    accent: Color(0xFF4FBDB4),
    accentFill: Color(0xFF4FBDB4),
    accentOn: Color(0xFF07100F),
    accentSoft: Color(0xFF1B2E2E),
    focusRing: Color(0xFF4FBDB4),
    code: AppCodeColors.dark,
  );

  /// True black, for OLED panels where a pure black pixel is genuinely off.
  /// Not merely "darker dark": the point is the unlit pixel, so the base is
  /// #000000 and elevation is carried by borders rather than lighter fills.
  ///
  /// The hairline is brighter here than in [dark] on purpose. With sunken, base
  /// and raised all collapsing toward black, the rails stop being surfaces and
  /// become regions defined only by their edges, so a border that reads as a
  /// hint in dark mode disappears entirely at low OLED brightness.
  static const AppTokens trueBlack = AppTokens(
    surfaceSunken: Color(0xFF000000),
    surfaceBase: Color(0xFF000000),
    surfaceRaised: Color(0xFF0B0D0F),
    borderSubtle: Color(0xFF2C3238),
    textPrimary: Color(0xFFF2F5F7),
    textSecondary: Color(0xFFA8B2BC),
    accent: Color(0xFF3FBFAE),
    accentFill: Color(0xFF3FBFAE),
    accentOn: Color(0xFF04100E),
    accentSoft: Color(0xFF132926),
    focusRing: Color(0xFF3FBFAE),
    code: AppCodeColors.trueBlack,
  );

  @override
  AppTokens copyWith({
    Color? surfaceSunken,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? accentFill,
    Color? accentOn,
    Color? accentSoft,
    Color? focusRing,
    AppCodeColors? code,
  }) {
    return AppTokens(
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentOn: accentOn ?? this.accentOn,
      accentSoft: accentSoft ?? this.accentSoft,
      focusRing: focusRing ?? this.focusRing,
      code: code ?? this.code,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accentOn: Color.lerp(accentOn, other.accentOn, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      code: t < 0.5 ? code : other.code,
    );
  }
}

/// Syntax colours for fenced code blocks, five roles per theme.
///
/// Per theme because the same string colour cannot clear 4.5:1 on both white
/// and black, and a code block is exactly the surface that quietly ends up the
/// one inaccessible thing in an otherwise AA product.
@immutable
class AppCodeColors {
  const AppCodeColors({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.punctuation,
  });

  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color punctuation;

  static const AppCodeColors light = AppCodeColors(
    keyword: Color(0xFF8A3FA0),
    string: Color(0xFF0F7A5A),
    number: Color(0xFF9A5B00),
    comment: Color(0xFF6B7280),
    punctuation: Color(0xFF4A5158),
  );

  static const AppCodeColors dark = AppCodeColors(
    keyword: Color(0xFFD9A2E8),
    string: Color(0xFF7FD2A8),
    number: Color(0xFFE0B274),
    comment: Color(0xFF8B939C),
    punctuation: Color(0xFFB9C1C9),
  );

  static const AppCodeColors trueBlack = AppCodeColors(
    keyword: Color(0xFFDFAAEE),
    string: Color(0xFF8ADCB2),
    number: Color(0xFFE8BC80),
    comment: Color(0xFF949CA6),
    punctuation: Color(0xFFC4CCD4),
  );

  /// Every role, for a contrast gate that must not miss one.
  List<Color> get all => [keyword, string, number, comment, punctuation];
}

/// Colours for objects drawn on the Voice Canvas.
///
/// Deliberately warmer and more saturated than the chrome. The canvas is the
/// one place allowed more energy, and the energy is meant to come from the
/// content rather than from restyling the app around it.
///
/// [cursors] is a closed set of six categorical hues for remote participants.
/// They must not reuse the status hues or the accent, or a cursor reads as a
/// presence indicator.
abstract final class AppCanvasColors {
  static const Color annotation = Color(0xFFE86A5C);
  static const Color note = Color(0xFFE8B04B);
  static const Color shape = Color(0xFF5B8FD6);

  static const List<Color> cursors = [
    Color(0xFFE0699A),
    Color(0xFF8C6FE0),
    Color(0xFF3FA9C9),
    Color(0xFFD98A3F),
    Color(0xFF6FBF73),
    Color(0xFFC96FB8),
  ];
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
///
/// Three steps plus full. A 4dp and a 6dp corner are indistinguishable under a
/// 1px hairline, so the extra step bought nothing except one more judgement
/// call per contributor.
abstract final class AppRadii {
  static const double control = 6;
  static const double card = 10;
  static const double window = 16;
  static const double full = 999;
}

/// How wide a message column is allowed to get.
///
/// Line length, not layout: 15sp at 1.45 stops being comfortable to read well
/// before a wide monitor runs out of room.
const double kMessageColumnMax = 760;

/// Builds a theme from the token set, so widgets read colours from tokens and
/// never from raw literals. Shared by the app and the golden tests, which is
/// what keeps goldens representative of what ships.
ThemeData buildTheme(Brightness brightness, AppTokens tokens) {
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accentFill,
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
