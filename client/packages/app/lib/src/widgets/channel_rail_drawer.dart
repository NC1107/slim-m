// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The compact layout's edge-swipe route to the channel rail, and the second
/// half of that swipe: carrying it further opens the full-screen channel list.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routing/routes.dart';
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

  /// How far the drawer has been dragged on past its open edge.
  double _carried = 0;

  /// How far past open a drag has to carry before it commits to the
  /// full-screen list.
  ///
  /// The same 80 [DrawerEdgeSwipe] uses to decide an edge drag meant the
  /// drawer at all, so opening and going the rest of the way ask for the same
  /// travel rather than two numbers a hand would have to learn separately.
  static const double _commitDistance = 80;

  void _onPointerMove(PointerMoveEvent event) {
    // Vertical wins ties, so scrolling the rail never accumulates its jitter.
    if (event.delta.dx.abs() <= event.delta.dy.abs()) return;
    // Leftward is Flutter's own drag-to-close; only the far side is ours.
    if (event.delta.dx < 0) {
      _carried = 0;
      return;
    }
    _carried += event.delta.dx;
    if (_carried < _commitDistance) return;
    _carried = 0;
    Scaffold.of(context).closeDrawer();
    context.go(Routes.channels);
  }

  /// A [Listener], never a [GestureDetector].
  ///
  /// A detector here would enter the gesture arena and win it, being deeper in
  /// the tree than the whole-screen drag Flutter's own `DrawerController` uses
  /// to pull the drawer closed - so claiming the horizontal axis to read the
  /// rightward half would take the leftward half away with it, and dragging
  /// the rail shut would stop working. `channel_rail_drawer_test.dart`'s own
  /// "dragging the rail closed dismisses it" caught exactly that. A listener
  /// observes the same pointers without claiming anything.
  @override
  Widget build(BuildContext context) => Drawer(
    child: Listener(
      onPointerDown: (_) => _carried = 0,
      onPointerMove: _onPointerMove,
      child: const ChannelRail(),
    ),
  );
}
