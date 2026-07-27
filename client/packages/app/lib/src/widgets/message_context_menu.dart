// SPDX-License-Identifier: Apache-2.0
/// The message row's context menu: right-click on desktop, long-press on
/// touch, offering copy always and edit/delete/pin wherever the caller says
/// each is allowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row.dart';

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
}

/// Wraps [child] so a right-click or long-press over it opens a menu for
/// [content] and [actions], anchored to this region.
///
/// Meant to sit inside a [MessageRow]'s hover-reveal scope. Opening the menu
/// pins the row exactly like the reaction picker does in `emoji_picker.dart`:
/// without it, the pointer leaving the row for the menu (which sits below
/// and to the side of it) would unmount both before a tap could land.
class MessageContextMenuRegion extends StatefulWidget {
  const MessageContextMenuRegion({
    super.key,
    required this.content,
    required this.actions,
    required this.child,
  });

  final String content;
  final MessageActions actions;
  final Widget child;

  @override
  State<MessageContextMenuRegion> createState() =>
      _MessageContextMenuRegionState();
}

class _MessageContextMenuRegionState extends State<MessageContextMenuRegion> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _setOpen(bool open) {
    HoverRevealScope.maybeOf(context)?.pin(open);
    open ? _controller.show() : _controller.hide();
  }

  void _run(VoidCallback action) {
    _setOpen(false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(24, 12),
          child: TapRegion(
            onTapOutside: (_) => _setOpen(false),
            child: AppMenu(
              width: 200,
              children: [
                AppMenuItem(
                  label: 'Copy text',
                  leading: AppIcons.copy,
                  onTap: () => _run(() =>
                      Clipboard.setData(ClipboardData(text: widget.content))),
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
        child: GestureDetector(
          onSecondaryTapDown: (_) => _setOpen(true),
          onLongPress: () => _setOpen(true),
          child: widget.child,
        ),
      ),
    );
  }
}
