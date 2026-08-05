// SPDX-License-Identifier: Apache-2.0
/// One row in the message list: the avatar or continuation gutter, the
/// header line, the body, and everything that can follow it.
///
/// The avatar/gutter and header live in `message_row_identity.dart`, and the
/// hover-reveal mechanism (shared with the emoji picker and the context
/// menu) lives in `hover_reveal.dart`; both were split out to keep this file
/// to the row's own composition.
///
/// The background fill answers `hovered || menuOpen` rather than `hovered`
/// alone: `menuOpen` is `HoverReveal`'s own signal that this row's context
/// menu is showing by any gesture, long press included, which `hovered`
/// cannot answer since a long press deliberately never pins it (see
/// `HoverReveal`'s own doc for why). AppListRow's own hover token is reused
/// rather than a second hover convention.
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
import 'reply_quote.dart';

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
    this.dayLabel,
    required this.knownUsernames,
    required this.onRetry,
    required this.onDiscard,
    this.onEditFailed,
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
    this.threadReplyCount,
    this.threadLastReplyAt,
    this.replyTo,
    this.onReplyTap,
  });

  final Message message;

  /// True for a continuation of the same author's previous message inside
  /// the density's grouping window: drops the avatar and header, and shows
  /// the time in the gutter instead.
  final bool grouped;

  final bool showNewDivider;

  /// A formatted calendar-day label ("Today", "Yesterday", "July 28, 2026")
  /// shown as a divider above this row when it is the first message of a new
  /// day. Null on every other row. Decided by the caller for the same reason
  /// [grouped] is: only the list knows what came before this row.
  final String? dayLabel;

  /// Lower-cased usernames the mention renderer treats as real. See
  /// [MessageBody].
  final Set<String> knownUsernames;

  /// The deployment's custom emoji, name to id. Resolves a `:shortcode:` in
  /// the body ([MessageBody]) and on a reaction chip ([ReactionsRow]) alike.
  final Map<String, String> customEmoji;

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Recovers a failed message's text for editing (error grammar 01: failed
  /// content is never thrown away). Null hides the Edit action.
  final VoidCallback? onEditFailed;

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

  /// Undeleted replies in this message's thread, from
  /// `MessageExtras.threadReplyCount` - null (not zero) hides the row
  /// entirely, since a message with no thread must never read as a
  /// zero-reply one. See `ThreadReplySummary`.
  final int? threadReplyCount;

  /// When the thread's newest reply was sent, unix milliseconds. Null
  /// whenever [threadReplyCount] is null or zero.
  final int? threadLastReplyAt;

  /// The message [message] replies to, resolved by the transcript, or null
  /// when [message] is not a reply at all or its parent could not be
  /// resolved. See `reply_quote.dart` for what null does and does not mean.
  final Message? replyTo;

  /// Jumps to the parent named by [Message.replyToId]. Only ever called when
  /// that id is non-null, so it is safe to leave null when [message] is not
  /// a reply.
  final VoidCallback? onReplyTap;

  bool get _unsent => message.pending || message.failed;

  /// Exposed so a test can find the hover/menu-open background fill without
  /// depending on widget tree shape.
  static const Key hoverFillKey = Key('message_row_hover_fill');

  @override
  Widget build(BuildContext context) {
    final compact = LayoutClass.of(context) == LayoutClass.compact;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return HoverReveal(
      builder: (context, hovered, menuOpen) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dayLabel != null) DayDivider(label: dayLabel!),
          if (showNewDivider) const NewMessagesDivider(),
          MessageContextMenuRegion(
            content: message.content,
            actions: actions,
            onAddReaction: () =>
                showEmojiPickerSheet(context, onSelect: onPickReaction),
            // A failed row is marked by a red hairline down its left edge
            // (error grammar 01) - the row itself stays at full strength,
            // because its content is still the author's to act on.
            child: Stack(
              children: [
                // Full-bleed, edge to edge; see this file's own doc comment.
                Positioned.fill(
                  child: AnimatedContainer(
                    key: MessageRow.hoverFillKey,
                    duration: AppMotion.reduced(context, AppMotion.fast),
                    curve: AppMotion.entrance,
                    color: hovered || menuOpen
                        ? tokens.surfaceRaised
                        : Colors.transparent,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: message.failed
                        ? Border(
                            left: BorderSide(
                              color: tokens.dangerBorder,
                              width: 2,
                            ),
                          )
                        : const Border(),
                  ),
                  child: Padding(
                    // Top-only: a bottom inset here doubled the next row's top inset.
                    padding: EdgeInsets.fromLTRB(
                      compact
                          ? AppSizes.paneGutterCompact
                          : AppSizes.paneGutter,
                      grouped
                          ? AppDensity.normal.groupedRowGap
                          : AppDensity.normal.rowGap,
                      compact
                          ? AppSizes.paneGutterCompact
                          : AppSizes.paneGutter,
                      0,
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
                          // Align loosens Expanded's tight width so the cap can
                          // bite: without it the max was silently a no-op and body
                          // text ran the full pane on any monitor.
                          child: Align(
                            alignment: Alignment.topLeft,
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
                                  if (message.replyToId != null)
                                    ReplyQuote(
                                      resolved: replyTo,
                                      onTap: onReplyTap ?? () {},
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
                                      dim: message.pending,
                                    ),
                                  if (message.editedAt != null && !editing)
                                    const EditedMarker(),
                                  if (poll != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: AppSpacing.s4,
                                      ),
                                      child: PollView(
                                        poll: poll!,
                                        onVote: onVote,
                                      ),
                                    ),
                                  for (final attachment in attachments)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: AppSpacing.s4,
                                      ),
                                      child: AttachmentView(
                                        attachment: attachment,
                                      ),
                                    ),
                                  if (!_unsent)
                                    ReactionsRow(
                                      reactions: reactions,
                                      onReactionTap: onReactionTap,
                                      onPickReaction: onPickReaction,
                                      customEmoji: customEmoji,
                                    ),
                                  if ((threadReplyCount ?? 0) > 0)
                                    ThreadReplySummary(
                                      replyCount: threadReplyCount!,
                                      lastReplyAt: threadLastReplyAt,
                                      onTap: actions.canOpenThread
                                          ? actions.onOpenThread
                                          : null,
                                    ),
                                  if (message.failed)
                                    FailedRow(
                                      onRetry: onRetry,
                                      onEdit: onEditFailed,
                                      onDiscard: onDiscard,
                                      reason: message.failureReason,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Outside layout: revealing it must not resize the row.
                if (hovered && !_unsent)
                  Positioned(
                    top: 0,
                    right: compact
                        ? AppSizes.paneGutterCompact
                        : AppSizes.paneGutter,
                    child: _HoverActions(onPickReaction: onPickReaction),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating action cluster a hovered message shows, pinned to its top
/// right and drawn over the row rather than inside it.
///
/// A surface of its own so it reads as chrome rather than content: a bare
/// button laid straight onto the transcript is hard to tell from a reaction
/// chip, which is the thing directly below it.
class _HoverActions extends StatelessWidget {
  const _HoverActions({required this.onPickReaction});

  final ValueChanged<String> onPickReaction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: EmojiPickerButton(onSelect: onPickReaction),
      ),
    );
  }
}
