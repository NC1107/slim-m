// SPDX-License-Identifier: Apache-2.0
/// Motion, and the one question every animated widget in this system has to
/// ask before it moves anything.
///
/// The design language allows no decorative motion in the chrome, and decision
/// 0004 allows exactly one thing that loops: the speaking ring. Everything
/// animated routes its duration through [AppMotion.reduced], so honouring the
/// OS setting is one call rather than a policy each widget reinvents.
///
/// Deliberately not covered: a busy spinner. iOS and Android both keep their
/// own activity indicators spinning under reduce-motion, because a frozen
/// spinner reads as a hung app rather than as a calmer one, and matching the
/// platform matters more here than a literal reading of the setting.
library;

import 'package:flutter/widgets.dart';

/// Durations and the reduce-motion signal.
abstract final class AppMotion {
  /// Press and hover micro-feedback. The design language's `duration.fast`.
  static const Duration fast = Duration(milliseconds: 100);

  /// Panel and route transitions. The design language's `duration.base`.
  static const Duration base = Duration(milliseconds: 180);

  /// Modal entrances, and the chrome's ceiling: nothing here runs longer.
  /// The design language's `duration.slow`.
  static const Duration slow = Duration(milliseconds: 280);

  /// The one standard ease-out for entrances, and its accelerating
  /// counterpart for exits, named once so every transition agrees.
  static const Curve entrance = Curves.easeOut;
  static const Curve exit = Curves.easeIn;

  /// One direction of the speaking ring's pulse. It reverses, so a full cycle
  /// is twice this; the chrome's 280ms ceiling governs transitions, not a loop.
  static const Duration speakingPulse = Duration(milliseconds: 600);

  /// Whether this viewer has asked for less motion.
  ///
  /// Two signals rather than one. `disableAnimations` is the OS reduce-motion
  /// switch. `accessibleNavigation` is a screen reader being on, where a loop
  /// is movement nobody sees and a transition is only a delay in front of the
  /// next announcement; Flutter's own material widgets read it the same way.
  static bool isReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  /// [full], or nothing at all when the viewer has asked for less motion.
  ///
  /// Zero rather than merely quick: a 20ms tween is still a tween, and it is
  /// the state change that carries the meaning, never the travel between.
  static Duration reduced(BuildContext context, Duration full) =>
      isReduced(context) ? Duration.zero : full;
}
