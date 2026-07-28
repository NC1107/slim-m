// SPDX-License-Identifier: Apache-2.0
/// The type system: two families, three weights, six sizes.
///
/// From the 2026-07-26 visual identity review. Three constraints are worth
/// knowing before adding to this file:
///
/// - **Weight stops at 600.** There is no bold 700 in this system. Emphasis
///   comes from weight *and* colour together, and a fourth stop only gives
///   contributors another judgement call to get wrong.
/// - **Six sizes, and 17px was deliberately dropped.** It never appeared next
///   to 15px body without also differing in weight and colour, so it carried
///   no information the pair did not already carry.
/// - **Sizes are in logical pixels and do not scale with density.** Density is
///   a user setting that changes vertical rhythm only; type, avatars and touch
///   targets hold still, or a compact layout stops being readable rather than
///   becoming denser.
library;

import 'package:flutter/widgets.dart';

/// Font families. Both ship with the app rather than being resolved from the
/// system, so a Linux box without IBM Plex installed does not silently fall
/// back to something with different metrics and break every layout.
abstract final class AppFonts {
  /// Package-qualified because these ship inside `slimm_design_system`.
  /// A bare family name resolves to nothing from a consuming package and
  /// falls back silently, which is how the mono family ended up rendering
  /// as a proportional face.
  static const String sans = 'packages/slimm_design_system/IBM Plex Sans';
  static const String mono = 'packages/slimm_design_system/IBM Plex Mono';

  /// Colour emoji, per platform. Unnamed, fontconfig picks monochrome
  /// `Noto Emoji` over the colour face sitting beside it and every reaction
  /// renders as a hollow outline. A family absent from a machine is skipped.
  static const List<String> emoji = [
    'Noto Color Emoji',
    'Apple Color Emoji',
    'Segoe UI Emoji',
  ];
}

/// The three weights this system has. Named rather than raw [FontWeight] so
/// that "semi" is a decision recorded once instead of a w600 sprinkled around.
abstract final class AppWeights {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semi = FontWeight.w600;
}

/// Letter spacing, as a multiple of font size the way Flutter wants it in
/// logical pixels at the size each is used.
abstract final class AppTracking {
  /// Large text only. Tightening a title is what stops 24px reading as loose.
  static const double title = -0.015;

  /// Uppercase micro labels. Capitals set at 11px without extra tracking read
  /// as a solid block rather than as words.
  static const double label = 0.07;

  /// Monospace, which is otherwise slightly too tight at small sizes.
  static const double mono = 0.04;
}

/// The six-step type scale.
///
/// Each is a [TextStyle] with size and line height only: colour and weight are
/// applied at the call site, because the same size carries different meaning in
/// different roles and baking either in here would mean a variant per role.
abstract final class AppText {
  /// 11px. Timestamps, uppercase section labels, counts.
  static const TextStyle micro = TextStyle(fontSize: 11, height: 1.3);

  /// 12px. Dense secondary information that still has to be read, not scanned.
  static const TextStyle caption = TextStyle(fontSize: 12, height: 1.35);

  /// 14px. Interface text: rows, buttons, menu items.
  static const TextStyle ui = TextStyle(fontSize: 14, height: 1.3);

  /// 15px at 1.45. Message bodies, and the only style tuned for reading a
  /// paragraph rather than scanning a control.
  static const TextStyle body = TextStyle(fontSize: 15, height: 1.45);

  /// 20px. Section and dialog headings.
  static const TextStyle heading = TextStyle(fontSize: 20, height: 1.25);

  /// 24px. One per screen at most.
  static const TextStyle title = TextStyle(
    fontSize: 24,
    height: 1.2,
    letterSpacing: 24 * AppTracking.title,
  );

  /// An uppercase micro label, tracked out so capitals read as words.
  ///
  /// Its own accessor rather than a note in a doc comment, because every
  /// section label in the shell needs the same three properties and getting one
  /// of them wrong is invisible in isolation and obvious in a row of them.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: AppWeights.semi,
    letterSpacing: 11 * AppTracking.label,
  );

  /// Monospace at message-body size, for inline code and fenced blocks.
  static const TextStyle code = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 13.5,
    height: 1.5,
    letterSpacing: 13.5 * AppTracking.mono,
    fontFamilyFallback: AppFonts.emoji,
  );
}
