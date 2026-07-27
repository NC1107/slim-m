// SPDX-License-Identifier: Apache-2.0
/// A generic right-click/long-press context menu: the anchor and overlay
/// machinery `message_context_menu.dart` uses for a message row, extracted
/// so any other row (a member, say) can offer the same interaction over a
/// plain [AppMenu] item list rather than a message-shaped one.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Wraps [child] so a right-click or long-press opens an [AppMenu] built by
/// [itemsBuilder], anchored to this region. [itemsBuilder] receives a
/// `close` callback each item's `onTap` should call before acting, matching
/// the close-then-run order `message_context_menu.dart` uses.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.itemsBuilder,
    required this.child,
  });

  final List<Widget> Function(VoidCallback close) itemsBuilder;
  final Widget child;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _setOpen(bool open) => open ? _controller.show() : _controller.hide();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content: an overlay child is
        // otherwise laid out against the whole screen, which a Column fills.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(24, 12),
            child: TapRegion(
              onTapOutside: (_) => _setOpen(false),
              child: AppMenu(
                width: 200,
                children: widget.itemsBuilder(() => _setOpen(false)),
              ),
            ),
          ),
        ),
        child: GestureDetector(
          onSecondaryTapDown: (_) => _setOpen(true),
          onLongPress: () => _setOpen(true),
          child: widget.child,
        ),
      ),
    );
  }
}
