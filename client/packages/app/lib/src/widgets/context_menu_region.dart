// SPDX-License-Identifier: Apache-2.0
/// A generic right-click/long-press context menu: the anchor and overlay
/// machinery `message_context_menu.dart` uses for a message row, extracted
/// so any other row (a member, say) can offer the same interaction over a
/// plain [AppMenu] item list rather than a message-shaped one.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/breakpoints.dart';
import 'context_menu_focus.dart';

/// Wraps [child] so a right-click or long-press opens an [AppMenu] built by
/// [itemsBuilder], anchored to this region. [itemsBuilder] receives a
/// `close` callback each item's `onTap` should call before acting, matching
/// the close-then-run order `message_context_menu.dart` uses.
///
/// On a compact layout the menu is a bottom sheet, Discord-style, rather than
/// the floating follower: a floating menu opened by a long-press sits right
/// under the thumb that opened it. Wider layouts keep the floating overlay
/// unchanged, since a mouse anchors the menu to where it clicked instead.
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

  void _setOpen(bool open) {
    if (!open) {
      _controller.hide();
      return;
    }
    if (LayoutClass.of(context) == LayoutClass.compact) {
      _openSheet();
    } else {
      _controller.show();
    }
  }

  /// [showAppSheet] switches between a bottom sheet and a dialog by the same
  /// width [_setOpen] already checked, so calling it here only ever reaches
  /// its bottom-sheet branch.
  void _openSheet() {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AppMenu(
          children: widget.itemsBuilder(() => Navigator.of(sheetContext).pop()),
        ),
      ),
    );
  }

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
              child: ContextMenuKeyboardScope(
                onDismiss: () => _setOpen(false),
                child: AppMenu(
                  width: 200,
                  children: widget.itemsBuilder(() => _setOpen(false)),
                ),
              ),
            ),
          ),
        ),
        child: ContextMenuFocus(
          onOpen: () => _setOpen(true),
          child: GestureDetector(
            onSecondaryTapDown: (_) => _setOpen(true),
            onLongPress: () => _setOpen(true),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
