// SPDX-License-Identifier: Apache-2.0
/// The message row's context menu: right-click on desktop, long-press on
/// touch, offering copy always and edit/delete/pin wherever the caller says
/// each is allowed.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row.dart';

/// Where the menu's top-left sits relative to the row's own top-left, from
/// the design.
const Offset _menuInset = Offset(24, 12);

/// Kept off the viewport edges on top of whatever the safe area already
/// reserves, so a clamped menu does not sit flush against the screen.
const double _screenMargin = 8;

/// What the menu can do for one message. The caller (which knows authorship
/// and permissions; the menu deliberately does not) decides each `can*`
/// flag, so this stays a plain description rather than a policy.
class MessageActions {
  const MessageActions({
    required this.canEdit,
    required this.onEdit,
    required this.canDelete,
    required this.onDelete,
    required this.canManagePins,
    required this.pinned,
    required this.onTogglePin,
    required this.canReport,
    required this.onReport,
    required this.canBlockAuthor,
    required this.onBlockAuthor,
  });

  final bool canEdit;
  final VoidCallback onEdit;
  final bool canDelete;
  final VoidCallback onDelete;

  /// Gates the pin/unpin item; server-side this is MANAGE_MESSAGES,
  /// evaluated in the message's own channel.
  final bool canManagePins;

  /// The item reads "Unpin" when true, "Pin" otherwise. Meaningless when
  /// [canManagePins] is false, since the item is absent either way.
  final bool pinned;
  final VoidCallback onTogglePin;

  /// False for a message you authored: reporting your own content has
  /// nothing to investigate that deleting it would not already resolve.
  final bool canReport;
  final VoidCallback onReport;

  /// False for your own message and for one with no live author (a
  /// deleted account's content is anonymized and has nobody left to block).
  final bool canBlockAuthor;
  final VoidCallback onBlockAuthor;
}

/// Wraps [child] so a right-click or long-press over it opens a menu for
/// [content] and [actions], anchored to this region.
///
/// This is the only add-reaction affordance a finger has: the picker button
/// beside a message is revealed by a [MouseRegion] that touch never fires, so
/// [onAddReaction] is what makes reacting reachable at all on a phone.
class MessageContextMenuRegion extends StatefulWidget {
  const MessageContextMenuRegion({
    super.key,
    required this.content,
    required this.actions,
    required this.onAddReaction,
    required this.child,
  });

  final String content;
  final MessageActions actions;

  /// Opens the emoji picker for this message. Deliberately not part of
  /// [MessageActions]: that class is a set of `can*`/`on*` pairs a caller
  /// that knows permissions supplies, and reacting is ungated in this client
  /// exactly as the hover button has always been.
  final VoidCallback onAddReaction;

  final Widget child;

  @override
  State<MessageContextMenuRegion> createState() =>
      _MessageContextMenuRegionState();
}

class _MessageContextMenuRegionState extends State<MessageContextMenuRegion> {
  final _controller = OverlayPortalController();

  /// The list this row sits in, subscribed to only while the menu is open.
  ScrollPosition? _watched;

  /// The menu's preferred top-left in the overlay's coordinates, read when it
  /// opens. It does not follow the row, because every scroll closes it: a
  /// drag through [TapRegion.onTapOutside], and a wheel or a trackpad through
  /// [_closeOnScroll], which is what a pointer signal reaches instead. A
  /// signal fires no pointer down, so the tap region never sees it.
  Offset _anchor = Offset.zero;

  @override
  void dispose() {
    _watched?.removeListener(_closeOnScroll);
    super.dispose();
  }

  /// [pinRow] keeps the row's hover-revealed controls mounted so it does not
  /// reflow under an open menu. A long-press passes false: touch reveals
  /// nothing, so pinning would only mount a control the menu itself covers.
  void _setOpen(bool open, {bool pinRow = true}) {
    if (open) _anchor = _anchorOffset();
    _watchScroll(open);
    if (pinRow || !open) HoverRevealScope.maybeOf(context)?.pin(open);
    open ? _controller.show() : _controller.hide();
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

  Offset _anchorOffset() {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return _menuInset;
    return box.localToGlobal(_menuInset, ancestor: overlay);
  }

  void _run(VoidCallback action) {
    _setOpen(false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;

    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(
            anchor: _anchor,
            padding:
                MediaQuery.paddingOf(context) +
                const EdgeInsets.all(_screenMargin),
          ),
          child: TapRegion(
            onTapOutside: (_) => _setOpen(false),
            // Scrolls rather than overflowing where the whole menu cannot fit,
            // which a landscape phone at a large text scale reaches.
            child: SingleChildScrollView(
              child: AppMenu(
                width: 200,
                children: [
                  AppMenuItem(
                    label: 'Add reaction',
                    leading: AppIcons.smile,
                    onTap: () => _run(widget.onAddReaction),
                  ),
                  const AppMenuDivider(),
                  AppMenuItem(
                    label: 'Copy text',
                    leading: AppIcons.copy,
                    onTap: () => _run(
                      () => Clipboard.setData(
                        ClipboardData(text: widget.content),
                      ),
                    ),
                  ),
                  if (actions.canEdit)
                    AppMenuItem(
                      label: 'Edit',
                      leading: AppIcons.edit,
                      onTap: () => _run(actions.onEdit),
                    ),
                  if (actions.canManagePins)
                    AppMenuItem(
                      label: actions.pinned ? 'Unpin' : 'Pin',
                      leading: AppIcons.pin,
                      onTap: () => _run(actions.onTogglePin),
                    ),
                  if (actions.canReport || actions.canBlockAuthor) ...[
                    const AppMenuDivider(),
                    if (actions.canReport)
                      AppMenuItem(
                        label: 'Report message',
                        leading: AppIcons.report,
                        onTap: () => _run(actions.onReport),
                      ),
                    if (actions.canBlockAuthor)
                      AppMenuItem(
                        label: 'Block user',
                        leading: AppIcons.revoke,
                        tone: AppMenuItemTone.danger,
                        onTap: () => _run(actions.onBlockAuthor),
                      ),
                  ],
                  if (actions.canDelete) ...[
                    const AppMenuDivider(),
                    AppMenuItem(
                      label: 'Delete',
                      leading: AppIcons.delete,
                      tone: AppMenuItemTone.danger,
                      onTap: () => _run(actions.onDelete),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      child: GestureDetector(
        onSecondaryTapDown: (_) => _setOpen(true),
        onLongPress: () => _setOpen(true, pinRow: false),
        child: widget.child,
      ),
    );
  }
}

/// Places the menu at its anchor, sliding it back inside the viewport rather
/// than letting it run off an edge: a long-press on a message low on a phone
/// screen otherwise puts Delete past the bottom of the display.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.anchor, required this.padding});

  final Offset anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = size.width - padding.right - childSize.width;
    final maxY = size.height - padding.bottom - childSize.height;
    return Offset(
      anchor.dx.clamp(padding.left, math.max(padding.left, maxX)),
      anchor.dy.clamp(padding.top, math.max(padding.top, maxY)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}
