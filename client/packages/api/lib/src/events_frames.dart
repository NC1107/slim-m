// SPDX-License-Identifier: Apache-2.0
part of 'events.dart';

// A `part of` rather than its own library: `ServerEvent` is `sealed`, and Dart
// only allows a sealed class to be extended from inside its own library.

/// A message was deleted (soft, but gone from every live view).
class MessageDeleted extends ServerEvent {
  const MessageDeleted({required this.channelId, required this.messageId});

  final String channelId;
  final String messageId;
}

/// A message's reaction tallies changed. Carries the whole current set
/// rather than a delta, so a client can replace its stored counts outright
/// instead of reconciling an add or remove against what it already has.
class ReactionsChanged extends ServerEvent {
  const ReactionsChanged({
    required this.channelId,
    required this.messageId,
    required this.reactions,
  });

  final String channelId;
  final String messageId;
  final List<ReactionTally> reactions;
}

/// One emoji and its current public count, as broadcast live.
///
/// Deliberately a different type from [ReactionSummary] (in models.dart),
/// which is what a REST read of a message returns: that shape also carries
/// `reacted`, this one never does, because who reacted is per-viewer and the
/// server never broadcasts it. Keeping them distinct types means a caller
/// cannot accidentally read `.reacted` off a live update as if it were a
/// fetched one.
class ReactionTally {
  const ReactionTally({required this.emoji, required this.count});

  final String emoji;
  final int count;

  factory ReactionTally.fromJson(Map<String, dynamic> json) => ReactionTally(
        emoji: json['emoji'] as String,
        count: json['count'] as int,
      );
}

/// A message was pinned.
class MessagePinned extends ServerEvent {
  const MessagePinned({
    required this.channelId,
    required this.messageId,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  final String channelId;
  final String messageId;

  /// Null once that account has been anonymized, exactly as a message's own
  /// `authorId` is.
  final String? pinnedBy;
  final int pinnedAt;
}

/// A message was unpinned.
class MessageUnpinned extends ServerEvent {
  const MessageUnpinned({required this.channelId, required this.messageId});

  final String channelId;
  final String messageId;
}

/// A poll's tally changed. Carries the whole refreshed tally, never who cast
/// which vote.
class PollVoted extends ServerEvent {
  const PollVoted({
    required this.channelId,
    required this.messageId,
    required this.options,
  });

  final String channelId;
  final String messageId;
  final List<PollOptionTally> options;
}

/// One poll option's position and its current public vote count, as
/// broadcast live. Unlike [PollOption] (in models.dart), it carries no
/// `label`: a poll's options and their labels are fixed at creation and never
/// change, so only the tally needs to travel over the live update.
class PollOptionTally {
  const PollOptionTally({required this.position, required this.votes});

  final int position;
  final int votes;

  factory PollOptionTally.fromJson(Map<String, dynamic> json) =>
      PollOptionTally(
        position: json['position'] as int,
        votes: json['votes'] as int,
      );
}

/// A user's presence changed, from this receiving connection's point of view
/// (a user who chose to appear offline reaches everyone but themselves as
/// [PresenceState.offline]).
class PresenceChanged extends ServerEvent {
  const PresenceChanged({required this.userId, required this.status});

  final String userId;
  final PresenceState status;
}

/// A member was timed out, or their timeout was lifted.
///
/// Deployment-wide rather than channel-scoped, and carrying the deadline
/// rather than only an id: unlike presence there is nothing per-viewer to
/// resolve, since the badge is the same fact for everyone. Without this a
/// timed-out member's composer stays enabled and their sends start failing
/// with 403, which reads as the app being broken.
class MemberTimeoutChanged extends ServerEvent {
  const MemberTimeoutChanged({required this.userId, this.until});

  final String userId;

  /// Unix milliseconds, or null for a lift.
  final int? until;
}

/// A member was removed from the Space.
///
/// The removed member's own sockets close on the accompanying session
/// revocation; this is how everyone else's member list drops them without
/// waiting for a refetch.
class MemberRemoved extends ServerEvent {
  const MemberRemoved({required this.userId});

  final String userId;
}

/// Someone started typing in a channel. There is no explicit stop frame past
/// [TypingStopped]: the state also lapses on its own without a refresh.
class TypingStarted extends ServerEvent {
  const TypingStarted({required this.channelId, required this.userId});

  final String channelId;
  final String userId;
}

/// A typing indicator lapsed, or was superseded by a newer refresh.
class TypingStopped extends ServerEvent {
  const TypingStopped({required this.channelId, required this.userId});

  final String channelId;
  final String userId;
}
