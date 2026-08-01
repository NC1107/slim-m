// SPDX-License-Identifier: Apache-2.0
/// The compact layout's edge-swipe route to the channel rail.
library;

import 'package:flutter/material.dart';

import 'channel_rail.dart';

/// [ChannelRail] behind [Scaffold.drawer], for phone width.
///
/// This is the same widget the medium and expanded layouts dock beside the
/// conversation, here inside Flutter's own drawer machinery instead of a
/// hand-rolled one: the edge-drag gesture, the scrim, the open/close
/// animation and the modal semantics all come from [Scaffold] for free, the
/// way `HomeShell`'s member-pane `endDrawer` already gets them.
///
/// [ChannelRail]'s own row taps only navigate - they have no idea whether
/// they are docked or inside a drawer that ought to close over the choice.
/// Rather than thread a close callback through every row (three call sites
/// across two files), this widget watches the route's own answer to "which
/// channel is selected" and closes itself the moment that answer changes,
/// which is what selecting a channel here amounts to regardless of how the
/// route got there - a shortcut key cycling channels while this happens to
/// be open closes it exactly the same way a row tap does.
class CompactChannelRailDrawer extends StatefulWidget {
  const CompactChannelRailDrawer({required this.selectedChannelId, super.key});

  /// `selectedChannelId(context)`, read by [HomeShell] once and passed down
  /// so this widget never has to depend on the router directly.
  final String? selectedChannelId;

  @override
  State<CompactChannelRailDrawer> createState() =>
      _CompactChannelRailDrawerState();
}

/// Reachable only while a real `Drawer` is open, opening or closing - never
/// while fully dismissed - so there is no dismissed case to guard here.
/// [Scaffold.closeDrawer] itself reenters a build already under way (this
/// rebuild is the ancestor Scaffold's own), so the close waits a frame.
class _CompactChannelRailDrawerState extends State<CompactChannelRailDrawer> {
  @override
  void didUpdateWidget(CompactChannelRailDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedChannelId == oldWidget.selectedChannelId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scaffold.of(context).closeDrawer();
    });
  }

  @override
  Widget build(BuildContext context) => const Drawer(child: ChannelRail());
}
