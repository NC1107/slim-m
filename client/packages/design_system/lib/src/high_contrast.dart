// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The "increase contrast" preference's effect on the token set: a targeted
/// boost of the two weakest roles, not a second palette.
///
/// A full high-contrast theme is a design-token-lock decision (see
/// `docs/decisions/0004-visual-identity-review.md`), and this is deliberately
/// not that. It reuses two values the token set already defines -
/// [AppTokens.borderStrong] (declared for the menu, unused everywhere else)
/// and [AppTokens.textSecondary] - rather than inventing new colours, so the
/// accent, status and danger/warn hues, and the colour-blind guarantees they
/// carry, are untouched by this toggle entirely.
library;

import 'app_tokens.dart';

/// [AppTokens.borderSubtle] moves to [AppTokens.borderStrong] (a real edge
/// rather than a hairline hint), and [AppTokens.textDisabled] moves to
/// [AppTokens.textSecondary] (the weakest text role, the one
/// `contrast_test.dart` already reports rather than gates as WCAG-borderline,
/// reads as merely quiet instead).
///
/// Deliberately not applied to the token map `contrast_test.dart` gates:
/// this only ever runs on a copy an install opted into, so the disabled/
/// secondary distinction that test protects is untouched at the source.
AppTokens applyHighContrast(AppTokens tokens) => tokens.copyWith(
      borderSubtle: tokens.borderStrong,
      textDisabled: tokens.textSecondary,
    );
