// SPDX-License-Identifier: Apache-2.0
/// Spacing, radii, control sizes and the two shadows this system has.
///
/// Everything here is a closed set. The point of naming them is that a
/// contributor picks from a list instead of inventing a value, so adding a step
/// costs more than it looks: it is one more thing for the next person to choose
/// wrongly between.
library;

import 'package:flutter/widgets.dart';

/// The 4dp spacing grid, named by value.
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
}

/// Corner radii; elevation is border-first, so shadows are rare.
///
/// Three steps plus full. A 4dp and a 6dp corner are indistinguishable under a
/// 1px hairline, so the extra step bought nothing except one more judgement
/// call per contributor. [window] is reserved for floating canvas objects.
abstract final class AppRadii {
  static const double control = 6;
  static const double card = 10;
  static const double window = 16;
  static const double full = 999;
}

/// Minimum interactive sizes.
///
/// [rowPointer] and [rowTouch] are the same row at two input classes, not two
/// designs. A compact layout raises rows to the touch value; nothing else about
/// the row changes, because a row that also shrinks its type at touch size is
/// harder to hit *and* harder to read.
abstract final class AppSizes {
  static const double rowPointer = 30;
  static const double rowTouch = 44;

  static const double controlSm = 26;
  static const double controlMd = 34;
  static const double controlLg = 38;

  static const double icon16 = 16;
  static const double icon20 = 20;
  static const double icon24 = 24;
  static const double icon32 = 32;

  /// Lucide's own stroke width. Mixing stroke weights across an icon set is
  /// the fastest way to make a considered set look assembled from clip art.
  static const double iconStroke = 1.5;
}

/// The two shadows, for the two things that genuinely float.
///
/// Elevation is otherwise carried entirely by a 1px hairline. A shadow here is
/// a statement that something is above the plane rather than part of it, which
/// is true of a menu and a dragged canvas object and of nothing else.
abstract final class AppShadows {
  static const List<BoxShadow> menu = [
    BoxShadow(
      color: Color(0x6B000000),
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> float = [
    BoxShadow(
      color: Color(0x85000000),
      blurRadius: 64,
      offset: Offset(0, 24),
    ),
  ];
}

/// Vertical rhythm, which is the only thing the density setting moves.
///
/// Type sizes, avatar sizes and touch targets deliberately do not respond to
/// it. Someone choosing "compact" wants more messages on screen, not smaller
/// text, and conflating the two produces a mode nobody can read.
enum AppDensity {
  compact(rowGap: 4, groupWindow: Duration(minutes: 7)),
  normal(rowGap: 8, groupWindow: Duration(minutes: 5)),
  spacious(rowGap: 12, groupWindow: Duration(minutes: 3));

  const AppDensity({required this.rowGap, required this.groupWindow});

  /// Space between message rows.
  final double rowGap;

  /// How long after a message the same author's next one still counts as part
  /// of the same group and drops its avatar and header.
  final Duration groupWindow;
}

/// How wide a message column is allowed to get.
///
/// Line length, not layout: 15sp at 1.45 stops being comfortable to read well
/// before a wide monitor runs out of room.
const double kMessageColumnMax = 760;
