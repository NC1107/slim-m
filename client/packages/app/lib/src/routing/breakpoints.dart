// SPDX-License-Identifier: Apache-2.0
/// Layout classes, chosen by available width.
///
/// Width decides the layout, never the platform. A phone in landscape, a small
/// window on a desktop, and a tablet split-screen are the same problem, and
/// keying off Platform.isX gets all three wrong.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

enum LayoutClass {
  /// One pane at a time; navigating pushes.
  compact,

  /// Two panes: the channel list beside the conversation.
  medium,

  /// Two panes with room to spare, and space for a third later.
  expanded;

  static LayoutClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  /// [kCompactWidth] is shared with the design system, which raises hit
  /// targets to touch size at the same width: one pane and a finger are the
  /// same situation, and two thresholds for it would drift.
  static LayoutClass fromWidth(double width) => switch (width) {
        < kCompactWidth => LayoutClass.compact,
        < 1000 => LayoutClass.medium,
        _ => LayoutClass.expanded,
      };

  /// Whether the list and the conversation are visible at the same time.
  bool get showsBothPanes => this != LayoutClass.compact;
}
