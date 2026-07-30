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

import '../providers/channel_history.dart';
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
    required this.history,
    required this.onLoadOlder,
    required this.onRetryOlder,
    required this.actionsFor,
    required this.onRetry,
    required this.onDiscard,
    this.onEditFailed,
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

  /// How much of the channel is loaded. Only [ChannelHistory.atStart] lets the
  /// start-of-channel header render; anything else puts a loading affordance
  /// in its place, because the oldest loaded row is not known to be the first.
  final ChannelHistory history;

  /// Fired whenever the oldest end of the list comes into view, which the
  /// reverse below puts at the maximum scroll extent rather than the minimum.
  final VoidCallback onLoadOlder;
  final VoidCallback onRetryOlder;

  final MessageActionsFor actionsFor;

  final void Function(Message message) onRetry;
  final void Function(Message message) onDiscard;

  /// Recovers a failed message's text into the composer; see MessageRow.
  final void Function(Message message)? onEditFailed;
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

  /// How close to the oldest end still counts as having reached it, so a page
  /// starts before the reader hits a hard stop.
  static const double _loadOlderSlop = 240;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MessageTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) return;
    oldWidget.scrollController.removeListener(_onScroll);
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  /// The list is reversed, so the oldest message sits at the *maximum* extent;
  /// the minimum is the newest, which is where `_scrollToLatest` goes.
  void _onScroll() {
    final controller = widget.scrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.maxScrollExtent - position.pixels > _loadOlderSlop) return;
    widget.onLoadOlder();
  }

  /// A list shorter than its viewport never scrolls, so nothing would ever
  /// ask for the page that would prove where the channel starts.
  ///
  /// Called only once [build] is about to lay out a real, populated list.
  /// Every loaded row can be filtered from view (a channel whose visible tail
  /// is entirely a blocked author, say), and an empty transcript then renders
  /// as a bare [SingleChildScrollView] whose `maxScrollExtent` is always zero
  /// - indistinguishable, to [_onScroll], from a genuine scroll to the end.
  /// Gating on there being an actual list is a structural fact about what is
  /// on screen, not a threshold: a counter would still fire this once before
  /// it could trip, and forgets, the moment it resets, why it should not fire
  /// again the next time every row is filtered.
  ///
  /// Whether the ask is worth making is [ChannelHistoryController.loadOlder]'s
  /// decision alone; scheduling nothing once the start is known only saves the
  /// callback.
  void _checkAfterLayout() {
    if (widget.history.atStart) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  /// The start header only when the oldest loaded row is known to be the
  /// channel's first, and only where such a header belongs at all.
  Widget? _topSlot() {
    if (!widget.history.atStart) {
      return HistoryTopAffordance(
        failed: widget.history.failed,
        loading: widget.history.loading,
        onRetry: widget.onRetryOlder,
      );
    }
    if (widget.channelName == null) return null;
    return ChannelStartHeader(
      name: widget.channelName!,
      topic: widget.channelTopic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final start = _topSlot();

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

    _checkAfterLayout();
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
        final newDay = isNewDay(message, previous);
        final row = MessageRowExtras(
          // By message, not by slot: an arrival shifts every index by one.
          key: ValueKey(message.id),
          messageId: message.id,
          builder: (extras) => MessageRow(
            message: message,
            // A new day breaks a group so a continuation across midnight regains its avatar and header.
            grouped: isGrouped(message, previous) && !newDay,
            showNewDivider: startsUnread(message, previous, widget.lastReadSeq),
            dayLabel: newDay ? formatMessageDay(message.createdAt) : null,
            knownUsernames: widget.knownUsernames,
            customEmoji: widget.customEmoji,
            onRetry: () => widget.onRetry(message),
            onDiscard: () => widget.onDiscard(message),
            onEditFailed: widget.onEditFailed == null
                ? null
                : () => widget.onEditFailed!(message),
            onPickReaction: (emoji) => widget.onPickReaction(message, emoji),
            onReactionTap: (reaction) =>
                widget.onReactionTap(message, reaction),
            onVote: (option) => widget.onVote(message, option),
            reactions: extras.reactions,
            attachments: extras.attachments,
            poll: extras.poll,
            editing: message.id == widget.editingId,
            onSubmitEdit: (content) => widget.onSubmitEdit(message, content),
            onCancelEdit: widget.onCancelEdit,
            actions: widget.actionsFor(message),
          ),
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
