// SPDX-License-Identifier: Apache-2.0
/// Reactions, attachments, and polls, kept in memory rather than in the
/// local database.
///
/// `client/packages/data` has no columns for any of the three, and this is
/// deliberate rather than an oversight: every REST fetch that returns a
/// [api.Message] (send, list, sync, search) already carries all three in
/// full, so re-fetching the channel's recent messages on open (see
/// [ChannelScreen]) re-hydrates this cache correctly after a restart without
/// a schema migration. What would not survive a restart cleanly is any
/// state this cache holds that a REST fetch cannot reconstruct - and there
/// is none: even a locally-cast vote or reaction is only ever an optimistic
/// preview of what the next broadcast or fetch confirms anyway.
///
/// The one hazard this exists to guard against: the server builds a live
/// `message.created`/`message.edited` frame from a bare DTO that omits
/// reactions, attachments, and poll data (a known Phase 4 server gap this
/// client must not try to fix). [applyMessage] merges rather than
/// overwrites, so that omission can only ever fail to add new information -
/// it can never erase a better answer this cache already has cached from a
/// REST fetch.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';

/// One message's reactions, attachments, and poll, however much of each is
/// known so far.
class MessageExtras {
  const MessageExtras({
    this.reactions = const [],
    this.attachments = const [],
    this.poll,
  });

  final List<api.ReactionSummary> reactions;
  final List<api.Attachment> attachments;
  final api.Poll? poll;

  MessageExtras copyWith({
    List<api.ReactionSummary>? reactions,
    List<api.Attachment>? attachments,
    api.Poll? poll,
  }) => MessageExtras(
    reactions: reactions ?? this.reactions,
    attachments: attachments ?? this.attachments,
    poll: poll ?? this.poll,
  );

  static const empty = MessageExtras();
}

class MessageExtrasController
    extends StateNotifier<Map<String, MessageExtras>> {
  MessageExtrasController(this._ref) : super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen(_onEvent);
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _sub;

  MessageExtras extrasFor(String messageId) =>
      state[messageId] ?? MessageExtras.empty;

  void _onEvent(api.ServerEvent event) {
    switch (event) {
      case api.MessageCreated(:final message):
        applyMessage(message);
      case api.MessageEdited(:final message):
        applyMessage(message);
      case api.ReactionsChanged(:final messageId, :final reactions):
        _applyReactionsChanged(messageId, reactions);
      case api.PollVoted(:final messageId, :final options):
        _applyPollTally(messageId, options);
      default:
        break;
    }
  }

  /// Merges in whatever [message] carries. See the file doc comment for why
  /// a merge, never an overwrite, is what makes this safe to call from a
  /// live socket frame that may have omitted all three fields.
  void applyMessage(api.Message message) {
    final existing = state[message.id];
    _set(
      message.id,
      MessageExtras(
        reactions: message.reactions.isNotEmpty
            ? message.reactions
            : existing?.reactions ?? const [],
        attachments: message.attachments.isNotEmpty
            ? message.attachments
            : existing?.attachments ?? const [],
        poll: message.poll ?? existing?.poll,
      ),
    );
  }

  /// For a REST fetch's whole page at once (search, catch-up, or a channel
  /// screen hydrating its visible window on open).
  void applyMessages(Iterable<api.Message> messages) {
    for (final message in messages) {
      applyMessage(message);
    }
  }

  void _applyReactionsChanged(
    String messageId,
    List<api.ReactionTally> tallies,
  ) {
    final known = extrasFor(messageId).reactions;
    const unknown = api.ReactionSummary(emoji: '', count: 0, reacted: false);
    final next = [
      for (final tally in tallies)
        api.ReactionSummary(
          emoji: tally.emoji,
          count: tally.count,
          // `reacted` is per-viewer and never broadcast (see ReactionTally's
          // own doc comment), so this keeps whatever this client already
          // knew about its own reaction rather than guessing.
          reacted: known
              .firstWhere((r) => r.emoji == tally.emoji, orElse: () => unknown)
              .reacted,
        ),
    ];
    _set(messageId, extrasFor(messageId).copyWith(reactions: next));
  }

  /// Applies the caller's own reaction toggle immediately, ahead of the
  /// `reactions.changed` broadcast that eventually confirms it (the acting
  /// connection receives its own broadcast too, so this is a preview, not a
  /// permanent guess). Reverting on a failed request is the caller's job,
  /// by calling this again with [active] flipped.
  void applyLocalReactionToggle(String messageId, String emoji, bool active) {
    final existing = extrasFor(messageId).reactions;
    final index = existing.indexWhere((r) => r.emoji == emoji);
    final List<api.ReactionSummary> next;
    if (active) {
      next = [...existing];
      if (index >= 0) {
        final current = next[index];
        if (!current.reacted) {
          next[index] = api.ReactionSummary(
            emoji: emoji,
            count: current.count + 1,
            reacted: true,
          );
        }
      } else {
        next.add(api.ReactionSummary(emoji: emoji, count: 1, reacted: true));
      }
    } else {
      next = [...existing];
      if (index >= 0) {
        final current = next[index];
        final count = current.reacted ? current.count - 1 : current.count;
        if (count <= 0) {
          next.removeAt(index);
        } else {
          next[index] = api.ReactionSummary(
            emoji: emoji,
            count: count,
            reacted: false,
          );
        }
      }
    }
    _set(messageId, extrasFor(messageId).copyWith(reactions: next));
  }

  void _applyPollTally(String messageId, List<api.PollOptionTally> tallies) {
    final poll = extrasFor(messageId).poll;
    // Unknown until some REST fetch has taught this cache the question and
    // option labels; a bare tally has neither, so there is nothing to merge
    // it into yet. The next fetch that includes this message picks it up.
    if (poll == null) return;
    final byPosition = {for (final t in tallies) t.position: t.votes};
    final options = [
      for (final option in poll.options)
        api.PollOption(
          position: option.position,
          label: option.label,
          votes: byPosition[option.position] ?? option.votes,
        ),
    ];
    _set(
      messageId,
      extrasFor(messageId).copyWith(
        poll: api.Poll(
          question: poll.question,
          options: options,
          totalVotes: options.fold(0, (sum, o) => sum + o.votes),
          votedOption: poll.votedOption,
          closeAt: poll.closeAt,
          closed: poll.closed,
        ),
      ),
    );
  }

  /// Records the caller's own vote immediately, ahead of the `poll.voted`
  /// broadcast: that event never reports back who cast a vote, only the
  /// refreshed tally, so [Poll.votedOption] (per-viewer, never broadcast)
  /// would otherwise never update on the voter's own screen at all.
  void applyLocalVote(String messageId, int option) {
    final poll = extrasFor(messageId).poll;
    if (poll == null) return;
    final previous = poll.votedOption;
    if (previous == option) return;
    final options = [
      for (final o in poll.options)
        if (o.position == option)
          api.PollOption(
            position: o.position,
            label: o.label,
            votes: o.votes + 1,
          )
        else if (o.position == previous)
          api.PollOption(
            position: o.position,
            label: o.label,
            votes: (o.votes - 1).clamp(0, 1 << 31),
          )
        else
          o,
    ];
    _set(
      messageId,
      extrasFor(messageId).copyWith(
        poll: api.Poll(
          question: poll.question,
          options: options,
          totalVotes: options.fold(0, (sum, o) => sum + o.votes),
          votedOption: option,
          closeAt: poll.closeAt,
          closed: poll.closed,
        ),
      ),
    );
  }

  void _set(String id, MessageExtras extras) {
    state = {...state, id: extras};
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final messageExtrasProvider =
    StateNotifierProvider<MessageExtrasController, Map<String, MessageExtras>>(
      (ref) => MessageExtrasController(ref),
    );
