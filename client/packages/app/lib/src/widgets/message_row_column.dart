// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The column a message row lays out beside its avatar: header, reply quote,
/// body or edit field, the extras a message can carry, reactions, the thread
/// chip and the failed-send row.
///
/// Split out of `message_row.dart`, which owns the row's fill, hover toolbar
/// and menu, once that file reached the review budget's hard ceiling.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'app_surface_view.dart';
import 'attachment_view.dart';
import 'bot_ui_failure.dart';
import 'call_record_view.dart';
import 'embed_card.dart';
import 'forwarded_message_card.dart';
import 'link_preview_card.dart';
import 'message_buttons.dart';
import 'message_context_menu.dart';
import 'message_edit_field.dart';
import 'message_hover_toolbar.dart';
import 'message_inline.dart' show extractLinkPreviewUrls;
import 'message_row_identity.dart';
import 'message_row_parts.dart';
import 'message_text.dart';
import 'poll_view.dart';
import 'reactions_row.dart';
import 'reply_quote.dart';

class MessageRowColumn extends StatelessWidget {
  const MessageRowColumn({
    super.key,
    required this.message,
    required this.grouped,
    required this.compact,
    required this.editing,
    required this.actions,
    required this.knownUsernames,
    required this.knownRoleNames,
    required this.customEmoji,
    required this.onRetry,
    required this.onDiscard,
    required this.onReactionTap,
    required this.onVote,
    required this.onSubmitEdit,
    required this.onCancelEdit,
    this.onEditFailed,
    this.onViewEditHistory,
    this.onReplyTap,
    this.replyTo,
    this.webhookUsername,
    this.reactions = const [],
    this.attachments = const [],
    this.embeds = const [],
    this.components = const [],
    this.poll,
    this.appSurface,
    this.call,
    this.viewerIsCaller = false,
    this.threadReplyCount,
    this.threadLastReplyAt,
    this.threadUnreadCount,
  });

  final Message message;
  final bool grouped;
  final bool compact;
  final bool editing;
  final MessageActions actions;
  final Set<String> knownUsernames;
  final Set<String> knownRoleNames;
  final Map<String, String> customEmoji;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final ValueChanged<api.ReactionSummary> onReactionTap;
  final ValueChanged<int> onVote;
  final ValueChanged<String> onSubmitEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback? onEditFailed;
  final VoidCallback? onViewEditHistory;
  final VoidCallback? onReplyTap;
  final Message? replyTo;
  final String? webhookUsername;
  final List<api.ReactionSummary> reactions;
  final List<api.Attachment> attachments;
  final List<api.Embed> embeds;
  final List<api.ComponentRow> components;
  final api.Poll? poll;
  final api.AppSurface? appSurface;
  final api.CallRecord? call;
  final bool viewerIsCaller;
  final int? threadReplyCount;
  final int? threadLastReplyAt;
  final int? threadUnreadCount;

  bool get _unsent => message.pending || message.failed;

  @override
  Widget build(BuildContext context) {
    final edited = message.editedAt != null && !editing
        ? EditedMarker(onTap: onViewEditHistory)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!grouped)
          Padding(
            // Compact has no hover to reserve for, and no room to spare.
            padding: MessageHoverToolbar.clearance(compact: compact),
            child: MessageRowHeader(
              message: message,
              webhookUsername: webhookUsername,
              editing: editing,
            ),
          )
        else if (editing)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.s4),
            child: AppBadge(variant: AppBadgeVariant.role, label: 'Editing'),
          ),
        if (message.replyToId != null)
          ReplyQuote(resolved: replyTo, onTap: onReplyTap ?? () {}),
        if (editing)
          Padding(
            // The row is raised while editing; the field needs air above the fill's edge.
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: MessageEditField(
              initialContent: message.content,
              onSubmit: onSubmitEdit,
              onCancel: onCancelEdit,
            ),
          )
        // An attachment-only message has no body; an empty one still adds a blank line above the image. A forward's own note is often empty too.
        else if (message.content.isNotEmpty)
          Padding(
            // A headerless row's first line is what the toolbar would sit on.
            padding: grouped
                ? MessageHoverToolbar.clearance(compact: compact)
                : EdgeInsets.zero,
            child: MessageBody(
              content: message.content,
              messageId: message.id,
              knownUsernames: knownUsernames,
              knownRoleNames: knownRoleNames,
              customEmoji: customEmoji,
              dim: message.pending,
              announceSending: message.pending,
              trailing: edited,
            ),
          ),
        if (!editing && message.content.isNotEmpty)
          LinkPreviewList(urls: extractLinkPreviewUrls(message.content)),
        if (!editing && embeds.isNotEmpty) EmbedList(embeds: embeds),
        if (!editing && components.isNotEmpty)
          MessageButtons(
            channelId: message.channelId,
            messageId: message.id,
            rows: components,
            unavailable: message.authorId == null,
          ),
        BotUiFailureLine(messageId: message.id),
        if (message.forwarded case final forwarded?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: ForwardedMessageCard(
              forwarded: forwarded,
              body: forwarded.content.isEmpty
                  ? null
                  : MessageBody(
                      content: forwarded.content,
                      knownUsernames: knownUsernames,
                      knownRoleNames: knownRoleNames,
                      customEmoji: customEmoji,
                    ),
              attachments: attachments,
              currentChannelId: message.channelId,
            ),
          ),
        if (edited != null && message.content.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: edited),
        if (poll != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: PollView(poll: poll!, onVote: onVote),
          ),
        if (call != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: CallRecordView(
              record: call!,
              viewerIsCaller: viewerIsCaller,
            ),
          ),
        if (appSurface != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: AppSurfaceView(
              messageId: message.id,
              surface: appSurface!,
              title: appSurface!.moduleId,
            ),
          ),
        // A forward's attachments are part of what was forwarded, and are drawn inside its card instead.
        if (message.forwarded == null)
          for (final attachment in attachments)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: AttachmentView(
                attachment: attachment,
                siblings: openableImages(attachments),
              ),
            ),
        if (!_unsent)
          ReactionsRow(
            messageId: message.id,
            reactions: reactions,
            onReactionTap: onReactionTap,
            customEmoji: customEmoji,
          ),
        if ((threadReplyCount ?? 0) > 0)
          ThreadReplySummary(
            replyCount: threadReplyCount!,
            lastReplyAt: threadLastReplyAt,
            unread: (threadUnreadCount ?? 0) > 0,
            onTap: actions.canOpenThread ? actions.onOpenThread : null,
          ),
        if (message.failed)
          FailedRow(
            onRetry: onRetry,
            onEdit: onEditFailed,
            onDiscard: onDiscard,
            reason: message.failureReason,
          ),
      ],
    );
  }
}
