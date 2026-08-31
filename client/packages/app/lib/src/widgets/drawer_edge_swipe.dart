// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A left-edge drag that opens the ambient [Scaffold]'s start drawer.
///
/// `Drawer`'s own edge-swipe lives inside Flutter's `DrawerControllerState`,
/// which disables itself whenever `Theme.of(context).platform` reports a
/// desktop family - regardless of the window's actual width - so a desktop
/// window narrowed below `kCompactWidth` loses the gesture a phone at the
/// same width keeps. That is exactly the case `desktop-vs-mobile.md`'s one
/// rule forbids: layout (and the gestures that drive it) responds to window
/// width, never platform. This reimplements just the "swipe opens it" half
/// of that gesture, driven by drag distance alone with no platform check at
/// all, and is mounted only where the compact layout already put a drawer,
/// so it inherits that width gate rather than adding its own.
///
/// The strip starts past [kWindowResizeHandleThickness] while
/// [DesktopWindowShell.frameless] is active: that band is the frameless
/// window's own resize handle (`window_resize_frame.dart`), and a drag
/// starting inside it should resize the window, not open the drawer.
library;

import 'package:flutter/material.dart';

import '../desktop/desktop_window_shell.dart';
import '../desktop/window_resize_frame.dart';

/// How wide the left edge zone is: the band where a horizontal drag means
/// "open the drawer" and never anything else.
///
/// Wider than Flutter's own `drawerEdgeDragWidth` default of 20, and wide
/// enough to be an actual thumb target. It has to be one shared number rather
/// than a private one, because [SwipeToReply] has to refuse exactly this band:
/// before it did, the two gestures split the row between them and left the
/// drawer about four usable pixels - Flutter's `DrawerController` claims the
/// leftmost 20 whether or not it will act on them, so the strip only won from
/// 20 to 24, and every drag past 24 replied to a message instead. That is the
/// bug this constant exists to close; `drawer_edge_vs_swipe_to_reply_test.dart`
/// pins it.
const double kDrawerEdgeZoneWidth = 40;

/// Wraps [child] with the edge-drag strip; [child] still fills the space.
class DrawerEdgeSwipe extends StatefulWidget {
  const DrawerEdgeSwipe({required this.child, super.key});

  final Widget child;

  @override
  State<DrawerEdgeSwipe> createState() => _DrawerEdgeSwipeState();
}

class _DrawerEdgeSwipeState extends State<DrawerEdgeSwipe> {
  /// The shared edge zone; see [kDrawerEdgeZoneWidth].
  static const double _stripWidth = kDrawerEdgeZoneWidth;

  /// How far a drag has to travel right before it reads as "open the
  /// drawer" rather than a stray brush of the edge.
  static const double _openDistance = 80;

  double _dragged = 0;
  bool _opened = false;

  void _onDragStart(DragStartDetails _) {
    _dragged = 0;
    _opened = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_opened) return;
    _dragged += details.delta.dx;
    if (_dragged < _openDistance) return;
    _opened = true;
    Scaffold.of(context).openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final resizeHandleClaimsEdge = DesktopWindowShell.frameless;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          bottom: 0,
          left: resizeHandleClaimsEdge ? kWindowResizeHandleThickness : 0,
          width: _stripWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
          ),
        ),
      ],
    );
  }
}
