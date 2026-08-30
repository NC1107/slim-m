// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The channel rail's own slot in `HomeShell`'s row: the full rail, the
/// collapsed icon strip, or nothing at all, plus the drag handle that
/// toggles between the first two. Split out of `home_shell.dart`, which sat
/// at this repo's 500-line hard file limit before `CollapsedRailStrip`
/// pushed it past it.
///
/// The rail itself unmounts rather than sitting at zero width when
/// collapsed: it polls voice rosters while built, and a hidden pane must
/// not keep fetching. [CollapsedRailStrip] takes its place instead of the
/// width going all the way to zero, so settings/mic/deafen stay reachable
/// without ever mounting [ChannelRail]; see that widget's own doc for why
/// it is safe to leave mounted the whole time the rail is gone.
///
/// [showRail] already folds `!canvasFullscreen` into itself (`HomeShell`'s
/// own read of it), so this cannot tell "the user collapsed it" from "the
/// canvas asked for the whole pane" without [canvasFullscreen] too - the one
/// case where this slot goes to zero width and nothing at all. Returned as
/// a widget list, not a single wrapping widget, so both children still sit
/// directly in `HomeShell`'s own `Row` exactly as before this was split out.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'app_panel_reveal.dart';
import 'channel_rail.dart';
import 'collapsed_rail_strip.dart';
import 'rail_drag_handle.dart';

List<Widget> railSlot({
  required BuildContext context,
  required bool showRail,
  required bool canvasFullscreen,
  required double railWidth,
}) => [
  ClipRect(
    child: AnimatedContainer(
      duration: AppMotion.reduced(context, AppMotion.base),
      curve: AppMotion.entrance,
      width: showRail
          ? railWidth
          : canvasFullscreen
          ? 0
          : ChannelRail.collapsedWidth,
      child: showRail
          ? OverflowBox(
              minWidth: railWidth,
              maxWidth: railWidth,
              alignment: Alignment.centerRight,
              child: const AppPanelReveal(fromLeft: true, child: ChannelRail()),
            )
          : canvasFullscreen
          ? const SizedBox.shrink()
          : const CollapsedRailStrip(),
    ),
  ),
  // Always present, even collapsed: it is the only way back.
  if (!canvasFullscreen) const RailDragHandle(),
];
