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
import 'message_row_identity.dart';
import 'message_transcript_widgets.dart';

/// What a viewer may do to one message, decided by the screen because it is
/// the screen that knows who is looking and what they hold.
typedef MessageActionsFor = MessageActions Function(Message message);

class MessageTranscript extends StatefulWidget {
  const MessageTranscript({
    super.key,
    required this.messages,
    required this.syncStatus,
    this.channelName,
    this.channelTopic,
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

  /// The channel's name and topic, for the start-of-channel header above the
  /// oldest message. Null on a surface that has no such header (a DM, whose
  /// "name" is a person, or a voice channel), which simply omits it.
  final String? channelName;
  final String? channelTopic;

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
  State<MessageTranscript> createState() => _MessageTranscriptState();
}

class _MessageTranscriptState extends State<MessageTranscript> {
  /// Message ids already on screen at least once. The newest row animates in
  /// only when its id is not in here, so a genuinely new arrival slides in
  /// while the initial load, a recycle on scroll-back, and an unrelated parent
  /// rebuild all render it statically. Reset with the widget, which is per
  /// channel, so switching channels does not replay a stale entrance.
  final Set<String> _seen = {};
  bool _hydrated = false;

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final start = widget.channelName == null
        ? null
        : ChannelStartHeader(
            name: widget.channelName!,
            topic: widget.channelTopic,
          );

    if (messages.isEmpty) {
      // A brand-new channel is welcomed at the top; connecting and offline still say what they are.
      if (start != null && widget.syncStatus == SyncStatus.live) {
        return SingleChildScrollView(
          controller: widget.scrollController,
          child: start,
        );
      }
      return EmptyMessages(syncStatus: widget.syncStatus);
    }

    final newestId = messages.last.id;
    final animateNewest = _hydrated && !_seen.contains(newestId);
    // Everything on screen counts as seen, so a recycle never replays.
    _seen.addAll(messages.map((m) => m.id));
    _hydrated = true;

    // Reversed so a short conversation sits against the composer; the start header rides one past the oldest message, which reverse puts at the top.
    return ListView.builder(
      controller: widget.scrollController,
      reverse: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      itemCount: messages.length + (start != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (start != null && i == messages.length) return start;
        // Index 0 is the newest; `previous` stays the row visually above,
        // so grouping still reads right.
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index == 0 ? null : messages[index - 1];
        final extras = widget.extrasById[message.id] ?? MessageExtras.empty;
        final newDay = isNewDay(message, previous);
        final row = MessageRow(
          message: message,
          // A new day breaks a group so a continuation across midnight regains its avatar and header.
          grouped: isGrouped(message, previous) && !newDay,
          showNewDivider: startsUnread(message, previous, widget.lastReadSeq),
          dayLabel: newDay ? formatMessageDay(message.createdAt) : null,
          knownUsernames: widget.knownUsernames,
          customEmoji: widget.customEmoji,
          onRetry: () => widget.onRetry(message),
          onDiscard: () => widget.onDiscard(message),
          onPickReaction: (emoji) => widget.onPickReaction(message, emoji),
          onReactionTap: (reaction) => widget.onReactionTap(message, reaction),
          onVote: (option) => widget.onVote(message, option),
          reactions: extras.reactions,
          attachments: extras.attachments,
          poll: extras.poll,
          editing: message.id == widget.editingId,
          onSubmitEdit: (content) => widget.onSubmitEdit(message, content),
          onCancelEdit: widget.onCancelEdit,
          actions: widget.actionsFor(message),
        );
        if (i != 0) return row;
        return MessageEntrance(
          key: ValueKey('entrance-$newestId'),
          animateOnMount: animateNewest,
          child: row,
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

/// True when this message falls on a different calendar day than the one above
/// it, so a day divider lands exactly once at each day boundary. The oldest
/// loaded message ([previous] null) also counts, anchoring the top of the
/// transcript with the day it began.
bool isNewDay(Message message, Message? previous) {
  if (previous == null) return true;
  final a = DateTime.fromMillisecondsSinceEpoch(previous.createdAt);
  final b = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
  return a.year != b.year || a.month != b.month || a.day != b.day;
}
