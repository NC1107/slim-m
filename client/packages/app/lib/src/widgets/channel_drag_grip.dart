// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one place a finger can pick a channel row up.
///
/// A held press on the row belongs to its context menu and a plain drag on it
/// belongs to the rail's scroll, so lifting needs a handle of its own. It
/// starts only after a held press: a finger that merely scrolls across it
/// never lifts anything. See `docs/design/desktop-vs-mobile.md`, "drag to
/// reorder: long-press lifts".
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'rail_drag_lift.dart';

class ChannelDragGrip extends StatelessWidget {
  const ChannelDragGrip({
    super.key,
    required this.index,
    required this.channelName,
  });

  /// The row's position in the rail's flat item list.
  final int index;
  final String channelName;

  /// The width of a full touch target; the height is the row's own.
  static const double touchWidth = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: 'Reorder $channelName',
      hint: 'Press and hold, then drag',
      excludeSemantics: true,
      child: ReorderableDelayedDragStartListener(
        index: index,
        // Opaque, or only the glyph's own 16px would take the press.
        child: ColoredBox(
          color: Colors.transparent,
          child: SizedBox(
            width: touchWidth,
            height: AppListRow.heightFor(context),
            child: Center(
              child: RailGrabFeedback(
                child: Icon(
                  AppIcons.dragHandle,
                  size: AppSizes.icon16,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
