// SPDX-License-Identifier: Apache-2.0
/// The message row's context menu: right-click on desktop, long-press on
/// touch, offering copy always and edit/delete/pin wherever the caller says
/// each is allowed.
library;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'context_menu_region.dart';
import 'hover_reveal.dart';

/// What the menu can do for one message. The caller (which knows authorship
/// and permissions; the menu deliberately does not) decides each `can*`
/// flag, so this stays a plain description rather than a policy.
class MessageActions {
  const MessageActions({
    required this.canReply,
    required this.onReply,
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
    required this.canOpenThread,
    required this.onOpenThread,
  });

  /// Gated on SEND_MESSAGES in this channel, unlike [canEdit] and [canDelete]:
  /// replying is a new send, not an act on a message you already authored.
  final bool canReply;
  final VoidCallback onReply;

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

  /// Gated like [canReply] plus one more: never inside a thread already,
  /// since nesting is refused server-side. Opens the hidden sub-channel this
  /// message already has, or starts one.
  final bool canOpenThread;
  final VoidCallback onOpenThread;
}

/// Wraps [child] so a right-click or long-press over it opens a menu for
/// [content] and [actions] - the message-specific skin on [ContextMenuRegion],
/// which owns the gesture, the anchor, and the compact-sheet/wide-floating
/// split every context menu in the app now shares.
///
/// This is the only add-reaction affordance a finger has: the picker button
/// beside a message is revealed by a [MouseRegion] that touch never fires, so
/// [onAddReaction] is what makes reacting reachable at all on a phone.
///
/// The row tints across a hold, showing visible progress toward the threshold
/// instead of a dead finger (motion spec 10). It runs over the framework's own
/// long-press timeout rather than the spec's 350ms, because the gesture stays
/// a [GestureDetector] (the thing that publishes `SemanticsAction.longPress`)
/// and the tint has to end when the gesture it tracks does.
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
  /// True from finger-down until the long press commits or cancels; drives
  /// the hold-progress tint.
  bool _holding = false;

  /// The item list both the floating menu and the bottom sheet render,
  /// parameterised on how each closes itself: hiding the overlay controller
  /// for one, popping the sheet's own route for the other.
  List<Widget> _items(BuildContext context, VoidCallback close) {
    final actions = widget.actions;
    void run(VoidCallback action) {
      close();
      action();
    }

    return [
      AppMenuItem(
        label: 'Add reaction',
        leading: AppIcons.smile,
        onTap: () => run(widget.onAddReaction),
      ),
      if (actions.canReply)
        AppMenuItem(
          label: 'Reply',
          leading: AppIcons.reply,
          onTap: () => run(actions.onReply),
        ),
      if (actions.canOpenThread)
        AppMenuItem(
          label: 'Reply in thread',
          leading: AppIcons.thread,
          onTap: () => run(actions.onOpenThread),
        ),
      const AppMenuDivider(),
      AppMenuItem(
        label: 'Copy text',
        leading: AppIcons.copy,
        onTap: () =>
            run(() => Clipboard.setData(ClipboardData(text: widget.content))),
      ),
      if (actions.canEdit)
        AppMenuItem(
          label: 'Edit',
          leading: AppIcons.edit,
          onTap: () => run(actions.onEdit),
        ),
      if (actions.canManagePins)
        AppMenuItem(
          label: actions.pinned ? 'Unpin' : 'Pin',
          leading: AppIcons.pin,
          onTap: () => run(actions.onTogglePin),
        ),
      if (actions.canReport || actions.canBlockAuthor) ...[
        const AppMenuDivider(),
        if (actions.canReport)
          AppMenuItem(
            label: 'Report message',
            leading: AppIcons.report,
            onTap: () => run(actions.onReport),
          ),
        if (actions.canBlockAuthor)
          AppMenuItem(
            label: 'Block user',
            leading: AppIcons.revoke,
            tone: AppMenuItemTone.danger,
            onTap: () => run(actions.onBlockAuthor),
          ),
      ],
      if (actions.canDelete) ...[
        const AppMenuDivider(),
        AppMenuItem(
          label: 'Delete',
          leading: AppIcons.delete,
          tone: AppMenuItemTone.danger,
          onTap: () => run(actions.onDelete),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return ContextMenuRegion(
      itemsBuilder: _items,
      onOpenChanged: (open) => HoverRevealScope.maybeOf(context)?.pin(open),
      onHoldChanged: (holding) => setState(() => _holding = holding),
      child: AnimatedContainer(
        duration: _holding
            ? AppMotion.reduced(context, kLongPressTimeout)
            : AppMotion.reduced(context, AppMotion.fast),
        curve: Curves.linear,
        color: _holding
            ? tokens.accentSoft.withValues(alpha: 0.5)
            : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}
