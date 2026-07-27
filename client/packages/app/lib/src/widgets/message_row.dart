// SPDX-License-Identifier: Apache-2.0
/// One row in the message list: the avatar or continuation gutter, the
/// header line, the body, and everything that can follow it.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'attachment_view.dart';
import 'message_context_menu.dart';
import 'message_edit_field.dart';
import 'message_row_parts.dart';
import 'message_text.dart';
import 'poll_view.dart';
import 'user_avatar.dart';

/// The avatar column's width, and therefore also the continuation gutter's:
/// the design's 36px message-row avatar, named once so both agree.
const double _avatarSize = 36;

/// `HH:mm`, as the design uses throughout. Fixed width matters here: a
/// grouped message puts its time in a 36px gutter, and "12:05 PM" wraps to two
/// lines in it while "12:05" does not.
String formatMessageTime(int epochMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// One message, and optionally the "New" divider directly above it.
///
/// Grouping (dropping the avatar and header for a continuation) is decided by
/// the caller, which is what lets [ChannelScreen]'s tests exercise the rule
/// without needing a whole scrollable list.
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.message,
    required this.grouped,
    required this.showNewDivider,
    required this.knownUsernames,
    required this.onRetry,
    required this.onDiscard,
    required this.onPickReaction,
    required this.onReactionTap,
    required this.onVote,
    required this.actions,
    required this.editing,
    required this.onSubmitEdit,
    required this.onCancelEdit,
    this.isWebhook = false,
    this.reactions = const [],
    this.attachments = const [],
    this.poll,
  });

  final Message message;

  /// True for a continuation of the same author's previous message inside
  /// the density's grouping window: drops the avatar and header, and shows
  /// the time in the gutter instead.
  final bool grouped;

  final bool showNewDivider;

  /// Lower-cased usernames the mention renderer treats as real. See
  /// [MessageBody].
  final Set<String> knownUsernames;

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Called with the emoji character the [ReactionsRow] add-reaction picker
  /// chose.
  final ValueChanged<String> onPickReaction;

  /// Toggles the caller's own reaction for an existing chip: on if
  /// [api.ReactionSummary.reacted] was false, off if it was true.
  final ValueChanged<api.ReactionSummary> onReactionTap;

  /// Casts (or changes) the caller's vote when [poll] is non-null. Always
  /// required, like every other callback here, even though it is only ever
  /// invoked when there is a poll to vote on.
  final ValueChanged<int> onVote;

  /// What this row's context menu can do here: edit, delete, and pin/unpin,
  /// each gated by whatever the caller already knows about authorship and
  /// permissions.
  final MessageActions actions;

  /// True while this is the one row being edited inline. At most one row in
  /// a channel is ever true at once; [ChannelScreen] enforces that by
  /// keeping a single editing-message id, not this widget.
  final bool editing;

  /// Called with the trimmed new content when an inline edit is saved.
  final ValueChanged<String> onSubmitEdit;

  /// Called to leave edit mode without saving, however that happened
  /// (Escape, the Cancel button, or submitting empty text).
  final VoidCallback onCancelEdit;

  /// TODO(ui-backend): always false at every real call site. The schema's
  /// `Message` has no bot/webhook flag (there is no webhook or bot-account
  /// feature in this product at all yet), so nothing can set this true
  /// outside a test. It exists so the row shape the design specifies is
  /// built and exercised now rather than guessed at later.
  final bool isWebhook;

  /// Reaction summaries for this message, from `Message.reactions` (a REST
  /// fetch) merged with any live `reactions.changed` update; see
  /// `providers/message_extras.dart`.
  final List<api.ReactionSummary> reactions;

  /// Attachments riding on this message, in display order.
  final List<api.Attachment> attachments;

  /// The poll this message carries, if it is a poll message.
  final api.Poll? poll;

  bool get _unsent => message.pending || message.failed;

  @override
  Widget build(BuildContext context) {
    return _HoverReveal(
        builder: (context, hovered) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showNewDivider) const NewMessagesDivider(),
                MessageContextMenuRegion(
                  content: message.content,
                  actions: actions,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Leading(
                            grouped: grouped,
                            isWebhook: isWebhook,
                            message: message),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxWidth: kMessageColumnMax),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!grouped)
                                  _Header(
                                      message: message, isWebhook: isWebhook),
                                editing
                                    ? MessageEditField(
                                        initialContent: message.content,
                                        onSubmit: onSubmitEdit,
                                        onCancel: onCancelEdit,
                                      )
                                    : MessageBody(
                                        content: message.content,
                                        knownUsernames: knownUsernames,
                                        dim: _unsent,
                                      ),
                                if (message.editedAt != null && !editing)
                                  const EditedMarker(),
                                if (poll != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppSpacing.s4),
                                    child:
                                        PollView(poll: poll!, onVote: onVote),
                                  ),
                                for (final attachment in attachments)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppSpacing.s4),
                                    child:
                                        AttachmentView(attachment: attachment),
                                  ),
                                if (!_unsent)
                                  ReactionsRow(
                                    reactions: reactions,
                                    onReactionTap: onReactionTap,
                                    onPickReaction: onPickReaction,
                                    showAddButton: hovered,
                                  ),
                                if (message.failed)
                                  FailedRow(
                                      onRetry: onRetry, onDiscard: onDiscard),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ));
  }
}

/// Tracks pointer hover for one subtree.
///
/// Its own widget so [MessageRow] can stay stateless: the row has a dozen
/// fields and converting it wholesale to carry one bool would touch every
/// reference in the file.
class _HoverReveal extends StatefulWidget {
  const _HoverReveal({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<_HoverReveal> {
  bool _hovered = false;
  bool _pinned = false;

  void _pin(bool pinned) {
    if (_pinned != pinned) setState(() => _pinned = pinned);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: HoverRevealScope(
        pin: _pin,
        child: widget.builder(context, _hovered || _pinned),
      ),
    );
  }
}

/// Lets a hover-revealed control keep itself mounted while it has a popup open.
///
/// Without it, moving the pointer onto the popup leaves the row's [MouseRegion],
/// which unmounts the control and the popup with it - so the thing can be opened
/// and never clicked.
class HoverRevealScope extends InheritedWidget {
  const HoverRevealScope({
    super.key,
    required this.pin,
    required super.child,
  });

  final ValueChanged<bool> pin;

  /// Null outside a hover-revealed subtree, where nothing needs pinning.
  static HoverRevealScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HoverRevealScope>();

  @override
  bool updateShouldNotify(HoverRevealScope oldWidget) => pin != oldWidget.pin;
}

class _Leading extends StatelessWidget {
  const _Leading(
      {required this.grouped, required this.isWebhook, required this.message});

  final bool grouped;
  final bool isWebhook;
  final Message message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (grouped) {
      // The continuation gutter: no avatar, just the time, right-aligned so
      // it lines up with the avatar it replaces.
      return SizedBox(
        width: _avatarSize,
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            formatMessageTime(message.createdAt),
            textAlign: TextAlign.right,
            style: AppText.micro.copyWith(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    if (isWebhook) {
      return Container(
        width: _avatarSize,
        height: _avatarSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Icon(AppIcons.code,
            size: AppSizes.icon20, color: tokens.textSecondary),
      );
    }

    return AuthorAvatar(
      userId: message.authorId,
      name: _authorLabel(message),
      size: _avatarSize,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.message, required this.isWebhook});

  final Message message;
  final bool isWebhook;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _authorLabel(message),
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
          ),
          if (isWebhook) ...[
            const SizedBox(width: AppSpacing.s8),
            const AppBadge(variant: AppBadgeVariant.tag, label: 'webhook'),
          ],
          const SizedBox(width: AppSpacing.s8),
          Text(
            formatMessageTime(message.createdAt),
            style: AppText.micro.copyWith(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Never the raw id: a missing name means the row predates the server
/// sending names, and a 36-character uuid where a person's name goes reads as
/// corruption rather than staleness. A null author id is a deleted account,
/// which is a different and knowable thing.
String _authorLabel(Message message) =>
    message.authorDisplayName ??
    (message.authorId == null ? 'Deleted user' : 'Unknown');
