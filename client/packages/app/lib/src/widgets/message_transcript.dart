// SPDX-License-Identifier: Apache-2.0
/// A channel's messages, laid out: the reversed scroll, the grouping and
/// unread rules that decide what each row shows, and what an empty list means.
///
/// Split out of `channel_screen.dart` on the line between deciding and
/// drawing. Nothing here reaches the network or the store; everything it needs
/// arrives as a parameter, which is what lets the layout rules be tested
/// against a plain list of messages.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/message_extras.dart';
import '../providers/sync_controller.dart';
import 'message_context_menu.dart';
import 'message_row.dart';

/// What a viewer may do to one message, decided by the screen because it is
/// the screen that knows who is looking and what they hold.
typedef MessageActionsFor = MessageActions Function(Message message);

class MessageTranscript extends StatelessWidget {
  const MessageTranscript({
    super.key,
    required this.messages,
    required this.syncStatus,
    required this.scrollController,
    required this.lastReadSeq,
    required this.editingId,
    required this.knownUsernames,
    required this.customEmoji,
    required this.extrasById,
    required this.actionsFor,
    required this.onRetry,
    required this.onDiscard,
    required this.onPickReaction,
    required this.onReactionTap,
    required this.onVote,
    required this.onSubmitEdit,
    required this.onCancelEdit,
  });

  final List<Message> messages;

  /// Read only to tell an empty channel from one that has not caught up.
  final SyncStatus syncStatus;

  final ScrollController scrollController;
  final int lastReadSeq;

  /// The message swapped into its inline edit field, if any.
  final String? editingId;

  final Set<String> knownUsernames;
  final Map<String, String> customEmoji;
  final Map<String, MessageExtras> extrasById;
  final MessageActionsFor actionsFor;

  final void Function(Message message) onRetry;
  final void Function(Message message) onDiscard;
  final void Function(Message message, String emoji) onPickReaction;
  final void Function(Message message, api.ReactionSummary reaction)
  onReactionTap;
  final void Function(Message message, int option) onVote;
  final void Function(Message message, String content) onSubmitEdit;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return EmptyMessages(syncStatus: syncStatus);
    // Reversed so the design's bottom-filled column puts a short
    // conversation against the composer.
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        // Index 0 is the newest; `previous` stays the row visually above,
        // so grouping still reads right.
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index == 0 ? null : messages[index - 1];
        final extras = extrasById[message.id] ?? MessageExtras.empty;
        return MessageRow(
          message: message,
          grouped: isGrouped(message, previous),
          showNewDivider: startsUnread(message, previous, lastReadSeq),
          knownUsernames: knownUsernames,
          customEmoji: customEmoji,
          onRetry: () => onRetry(message),
          onDiscard: () => onDiscard(message),
          onPickReaction: (emoji) => onPickReaction(message, emoji),
          onReactionTap: (reaction) => onReactionTap(message, reaction),
          onVote: (option) => onVote(message, option),
          reactions: extras.reactions,
          attachments: extras.attachments,
          poll: extras.poll,
          editing: message.id == editingId,
          onSubmitEdit: (content) => onSubmitEdit(message, content),
          onCancelEdit: onCancelEdit,
          actions: actionsFor(message),
        );
      },
    );
  }
}

/// What an empty message list means depends on whether catch-up has actually
/// run: a channel can look empty because it is, or because sync has not
/// reached it yet, and those read as opposite things to the person waiting.
class EmptyMessages extends StatelessWidget {
  const EmptyMessages({super.key, required this.syncStatus});

  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return switch (syncStatus) {
      SyncStatus.connecting => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Catching up on messages...',
              style: TextStyle(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
      SyncStatus.offline => Center(
        child: Text(
          'Offline. Messages will appear once reconnected.',
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
      SyncStatus.live => Center(
        child: Text(
          'No messages yet.',
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
    };
  }
}

/// A continuation of the same author's previous message inside the density's
/// grouping window drops its avatar and header.
bool isGrouped(Message message, Message? previous) =>
    previous != null &&
    previous.authorId == message.authorId &&
    (message.createdAt - previous.createdAt).abs() <
        AppDensity.normal.groupWindow.inMilliseconds;

/// True for the first message past the read marker, so the "New" divider
/// lands exactly once, directly above it.
bool startsUnread(Message message, Message? previous, int lastReadSeq) =>
    message.seq > lastReadSeq &&
    (previous == null || previous.seq <= lastReadSeq);
