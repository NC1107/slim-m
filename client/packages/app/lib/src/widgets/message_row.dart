// SPDX-License-Identifier: Apache-2.0
/// One row in the message list: the avatar or continuation gutter, the
/// header line, the body, and everything that can follow it.
///
/// The avatar/gutter and header live in `message_row_identity.dart`, and the
/// hover-reveal mechanism (shared with the emoji picker and the context
/// menu) lives in `hover_reveal.dart`; both were split out to keep this file
/// to the row's own composition.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/breakpoints.dart';

import 'attachment_view.dart';
import 'emoji_picker.dart';
import 'hover_reveal.dart';
import 'message_context_menu.dart';
import 'message_edit_field.dart';
import 'message_row_identity.dart';
import 'message_row_parts.dart';
import 'message_text.dart';
import 'poll_view.dart';

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
    this.customEmoji = const {},
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

  /// The deployment's custom emoji, name to id. Resolves a `:shortcode:` in
  /// the body ([MessageBody]) and on a reaction chip ([ReactionsRow]) alike.
  final Map<String, String> customEmoji;

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Called with the token the add-reaction picker chose (a codepoint, or a
  /// `:shortcode:` for one of the deployment's own), from the hover-revealed
  /// button in [ReactionsRow] or from the long-press menu's own sheet, which
  /// is the only one of the two a finger can reach.
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
    final compact = LayoutClass.of(context) == LayoutClass.compact;
    return HoverReveal(
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showNewDivider) const NewMessagesDivider(),
          MessageContextMenuRegion(
            content: message.content,
            actions: actions,
            onAddReaction: () =>
                showEmojiPickerSheet(context, onSelect: onPickReaction),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSizes.paneGutterCompact : AppSizes.paneGutter,
                8,
                compact ? AppSizes.paneGutterCompact : AppSizes.paneGutter,
                4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MessageRowLeading(
                    grouped: grouped,
                    isWebhook: isWebhook,
                    message: message,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kMessageColumnMax,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!grouped)
                            MessageRowHeader(
                              message: message,
                              isWebhook: isWebhook,
                            ),
                          if (editing)
                            MessageEditField(
                              initialContent: message.content,
                              onSubmit: onSubmitEdit,
                              onCancel: onCancelEdit,
                            )
                          // An attachment-only message has no body; an empty one still adds a blank line above the image.
                          else if (message.content.isNotEmpty)
                            MessageBody(
                              content: message.content,
                              knownUsernames: knownUsernames,
                              customEmoji: customEmoji,
                              dim: _unsent,
                            ),
                          if (message.editedAt != null && !editing)
                            const EditedMarker(),
                          if (poll != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.s4,
                              ),
                              child: PollView(poll: poll!, onVote: onVote),
                            ),
                          for (final attachment in attachments)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.s4,
                              ),
                              child: AttachmentView(attachment: attachment),
                            ),
                          if (!_unsent)
                            ReactionsRow(
                              reactions: reactions,
                              onReactionTap: onReactionTap,
                              onPickReaction: onPickReaction,
                              customEmoji: customEmoji,
                              showAddButton: hovered,
                            ),
                          if (message.failed)
                            FailedRow(onRetry: onRetry, onDiscard: onDiscard),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
