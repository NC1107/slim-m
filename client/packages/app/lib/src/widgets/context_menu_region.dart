// SPDX-License-Identifier: Apache-2.0
/// The generic mechanism behind every right-click/long-press menu in the
/// app: the gesture, where it lands, the compact-sheet/wide-floating split,
/// and the keyboard route into it.
///
/// `MessageContextMenuRegion` wraps this rather than each keeping its own
/// copy - the exact shape report and block used to take, once per subject,
/// before both were collapsed into `safety_actions.dart`'s one implementation.
///
/// `ownsFocusNode: false` (an already-focusable child, an `AppListRow`)
/// deliberately publishes no screen-reader long-press action of its own,
/// unlike the message region. The first attempt used `MergeSemantics` to fold
/// the gesture's action into the row's own node, matching the message row's
/// shape; that silently swallowed a trailing kebab's own, separate tap
/// action, since `MergeSemantics` folds every descendant into one node
/// regardless of its own boundaries. `excludeFromSemantics` is used instead:
/// the row keeps exactly the semantics it already had, and a screen-reader
/// user reaches the menu through a connected keyboard's context-menu key
/// instead, which still works unaffected. See
/// `context_menu_region_reachability_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/breakpoints.dart';
import 'context_menu_focus.dart';
import 'message_context_menu_layout.dart';

/// Kept off the viewport edges on top of whatever the safe area already
/// reserves, so a clamped menu does not sit flush against the screen.
const double _screenMargin = 8;

/// Where the menu's top-left sits relative to the row's own top-left, used
/// only when nothing opened the menu with a pointer position at all - the
/// context-menu key, which carries no location to anchor to.
const Offset _rowInset = Offset(12, 12);

/// Nudges the menu's top-left off the exact pointer position that opened it,
/// so the cursor itself does not sit on top of the first item's hit box.
const Offset _pointerInset = Offset(4, 4);

/// Wraps [child] so a right-click or long-press over it opens a menu built by
/// [itemsBuilder], anchored under the pointer on a wide layout or presented
/// as a bottom sheet on a compact one.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.itemsBuilder,
    required this.child,
    this.onOpenChanged,
    this.onHoldChanged,
    this.ownsFocusNode = true,
  });

  /// Builds the menu's items given a callback that closes it. Called fresh
  /// every time the menu opens, so an item reflecting live state (a block
  /// flag, a permission) is never stale from an earlier open.
  final List<Widget> Function(BuildContext context, VoidCallback close)
  itemsBuilder;

  final Widget child;

  /// Told `true` right as the menu opens from a right-click and `false`
  /// right as it closes however that happens; never told `true` for a long
  /// press, which has no hover state on the touch device that sent it.
  /// `MessageContextMenuRegion` uses this to keep a row's hover-revealed
  /// controls mounted rather than reflowing under the open menu.
  final ValueChanged<bool>? onOpenChanged;

  /// Told `true` on press-down and `false` once the press is cancelled or
  /// commits, for a caller that shows hold progress across the long-press
  /// threshold. Null for a caller with no such visual.
  final ValueChanged<bool>? onHoldChanged;

  /// False when [child] is already its own tab stop (an [AppListRow], say),
  /// so the keyboard route rides that node instead of adding a second one.
  /// See [ContextMenuFocus.ownsFocusNode].
  final bool ownsFocusNode;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final _controller = OverlayPortalController();
  Offset _anchor = Offset.zero;
  bool _sheetOpen = false;

  /// The list this row sits in, subscribed to only while the menu is open,
  /// so a wheel or trackpad scroll (which fires no pointer down and so never
  /// reaches `TapRegion.onTapOutside`) still closes a menu the scroll just
  /// carried away from the row it was anchored to.
  ScrollPosition? _watched;

  @override
  void dispose() {
    _watched?.removeListener(_closeOnScroll);
    super.dispose();
  }

  /// [pinRow] mirrors [onOpenChanged]'s own doc: true (the default) for a
  /// right-click and every close, false for a long press, which has nothing
  /// to pin.
  ///
  /// [pointerGlobal] anchors the menu to wherever the gesture that opened it
  /// landed. A real long press calls this twice (`onLongPressStart` then the
  /// bare `onLongPress` immediately after, both fired by the one recognizer),
  /// so the anchor is only taken on the first of the two: recomputing it on
  /// the second call, which carries no position, would throw the real one away.
  void _setOpen(bool open, {bool pinRow = true, Offset? pointerGlobal}) {
    if (pinRow || !open) widget.onOpenChanged?.call(open);
    if (LayoutClass.of(context) == LayoutClass.compact) {
      _setSheetOpen(open);
      return;
    }
    if (open && !_controller.isShowing) _anchor = _anchorOffset(pointerGlobal);
    _watchScroll(open);
    open ? _controller.show() : _controller.hide();
  }

  void _setSheetOpen(bool open) {
    if (!open) {
      if (_sheetOpen) Navigator.of(context).maybePop();
      return;
    }
    if (_sheetOpen) return;
    _sheetOpen = true;
    showAppSheet<void>(
      context,
      bare: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AppSheetMenu(
          children: widget.itemsBuilder(
            sheetContext,
            () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    ).whenComplete(() => _sheetOpen = false);
  }

  void _closeOnScroll() {
    if (_controller.isShowing) _setOpen(false);
  }

  void _watchScroll(bool open) {
    final position = open ? Scrollable.maybeOf(context)?.position : null;
    if (identical(position, _watched)) return;
    _watched?.removeListener(_closeOnScroll);
    _watched = position;
    _watched?.addListener(_closeOnScroll);
  }

  /// Anchors at [pointerGlobal], converted into the overlay's own coordinate
  /// space, when a mouse or touch opened the menu. Falls back to a fixed
  /// offset from the region's own corner only when nothing did - the
  /// context-menu key, which has no pointer position to give.
  Offset _anchorOffset(Offset? pointerGlobal) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return _rowInset;
    if (pointerGlobal != null) {
      return overlay.globalToLocal(pointerGlobal) + _pointerInset;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return _rowInset;
    return box.localToGlobal(_rowInset, ancestor: overlay);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: MessageMenuLayout(
            anchor: _anchor,
            padding:
                MediaQuery.paddingOf(context) +
                const EdgeInsets.all(_screenMargin),
          ),
          child: TapRegion(
            onTapOutside: (_) => _setOpen(false),
            child: ContextMenuKeyboardScope(
              onDismiss: () => _setOpen(false),
              child: SingleChildScrollView(
                child: AppMenu(
                  width: 200,
                  children: widget.itemsBuilder(context, () => _setOpen(false)),
                ),
              ),
            ),
          ),
        ),
      ),
      child: ContextMenuFocus(
        onOpen: () => _setOpen(true),
        ownsFocusNode: widget.ownsFocusNode,
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _setOpen(true, pointerGlobal: details.globalPosition),
          // Kept out of the semantics tree once the child owns its own node; see this file's own doc comment for why.
          excludeFromSemantics: !widget.ownsFocusNode,
          // GestureDetector, never a raw recognizer: it is what publishes SemanticsAction.longPress, which context_menu_reachability_test guards.
          onLongPressDown: widget.onHoldChanged == null
              ? null
              : (_) => widget.onHoldChanged!(true),
          onLongPressCancel: widget.onHoldChanged == null
              ? null
              : () => widget.onHoldChanged!(false),
          // Carries the down position; bare onLongPress below fires right after it and carries none, kept only for its own SemanticsAction.longPress.
          onLongPressStart: (details) {
            widget.onHoldChanged?.call(false);
            _setOpen(
              true,
              pinRow: false,
              pointerGlobal: details.globalPosition,
            );
          },
          onLongPress: () => _setOpen(true, pinRow: false),
          child: widget.child,
        ),
      ),
    );
  }
}
