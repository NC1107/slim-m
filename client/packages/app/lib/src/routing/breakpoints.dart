// SPDX-License-Identifier: Apache-2.0
/// Layout classes, chosen by available width.
///
/// Width decides the layout, never the platform. A phone in landscape, a small
/// window on a desktop, and a tablet split-screen are the same problem, and
/// keying off Platform.isX gets all three wrong.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

import '../widgets/channel_rail.dart';
import '../widgets/member_pane.dart';

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

  /// Whether a docked member pane fits beside the rail and transcript at
  /// [width] without squeezing the transcript below the width
  /// [kCompactWidth] itself already treats as the minimum comfortable
  /// transcript: that boundary minus the medium rail's own width and its
  /// handle, the same arithmetic the compact/medium switch already rests on,
  /// reused here rather than a fresh number picked by feel.
  bool fitsMemberPane(double width) => _fitsThirdPane(width, AppMemberPane.width);

  /// Whether a docked thread pane fits, the same test as [fitsMemberPane] with
  /// the thread pane's own wider width. The thread pane and the member pane are
  /// mutually exclusive at the third-pane slot (opening a thread replaces the
  /// roster, the way Discord and Slack dock a thread), so only one third pane
  /// ever competes with the transcript at a time and this stays a single-pane
  /// fit test rather than a two-pane one.
  bool fitsThreadPane(double width) => _fitsThirdPane(width, kThreadPaneWidth);

  bool _fitsThirdPane(double width, double paneWidth) {
    if (this == LayoutClass.compact) return false;
    const minTranscript =
        kCompactWidth - ChannelRail.mediumWidth - AppSizes.rowPointer;
    final railWidth = this == LayoutClass.expanded
        ? ChannelRail.expandedWidth
        : ChannelRail.mediumWidth;
    return width - railWidth - AppSizes.rowPointer - paneWidth >= minTranscript;
  }
}

/// The docked thread pane's width: wider than the member pane because it holds
/// a transcript and composer, not a list, but still narrow enough to leave the
/// parent transcript above [_fitsThirdPane]'s minimum at the expanded boundary.
const double kThreadPaneWidth = 360;
