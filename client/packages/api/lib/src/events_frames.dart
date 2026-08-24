// SPDX-License-Identifier: Apache-2.0
part of 'events.dart';

// A `part of` rather than its own library: `ServerEvent` is `sealed`, and Dart
// only allows a sealed class to be extended from inside its own library.

/// A message was deleted (soft, but gone from every live view).
class MessageDeleted extends ServerEvent {
  const MessageDeleted({
    required this.channelId,
    required this.messageId,
    this.opSeq,
  });

  final String channelId;
  final String messageId;

  /// This delete's place in the channel's message-op stream, null against a
  /// server that has none.
  final int? opSeq;
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

/// A thread's reply summary changed: it was just opened, or gained a reply.
/// Carries the current count rather than a delta, the same "whole current
/// answer" shape [PollVoted] already uses, so a client that missed a frame
/// cannot drift.
///
/// [channelId] is the *parent* channel, not the thread's own - the channel a
/// receiving connection's gate is actually about. Unlike [ReactionsChanged]
/// the count is the same for every viewer regardless of blocking (the batch
/// reply-count load a REST fetch already uses is not per-viewer filtered
/// either), so it travels here directly rather than needing a re-derive.
class ThreadUpdated extends ServerEvent {
  const ThreadUpdated({
    required this.channelId,
    required this.parentMessageId,
    required this.threadChannelId,
    required this.replyCount,
    this.lastReplyAt,
  });

  final String channelId;
  final String parentMessageId;
  final String threadChannelId;
  final int replyCount;

  /// Unix milliseconds, or null exactly when [replyCount] is zero.
  final int? lastReplyAt;
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

/// The mirror of [MemberRemoved]: a removed member was let back in, so a
/// roster that dropped them should refetch rather than stay stale.
class MemberRestored extends ServerEvent {
  const MemberRestored({required this.userId});

  final String userId;
}

/// A user changed their display name. Carries only the id, never the new
/// name: the value lives in exactly one place, a user's own profile, and a
/// receiver re-asks for it (`SlimmApiUsers.getUser`/`listUsers`) rather than
/// trusting a second copy riding this frame.
class ProfileChanged extends ServerEvent {
  const ProfileChanged({required this.userId});

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

/// A role was created, renamed, had its permission bits changed, or was
/// deleted. Never carries the name or the bits: those are gated behind
/// MANAGE_ROLES over `GET /roles`, and this frame reaches every connection
/// regardless of whether it holds that. There is nothing to apply from the
/// id alone; a receiver re-asks what changed (its own permissions and
/// channel list, and its role list if it manages roles).
class RoleChanged extends ServerEvent {
  const RoleChanged({required this.roleId});

  final String roleId;
}

/// A role was granted to or revoked from a member. Carries both ids, which
/// is no more than `GET /members` already publishes for any caller.
class MemberRoleChanged extends ServerEvent {
  const MemberRoleChanged({required this.userId, required this.roleId});

  final String userId;
  final String roleId;
}

/// A channel was created, reaching a connection under the same
/// current-permission check [MessageCreated] already uses.
class ChannelCreated extends ServerEvent {
  const ChannelCreated(this.channel);

  final Channel channel;
}

/// A channel was renamed or had its topic replaced. Never changes what the
/// channel's permission model allows, so the same current-permission check
/// used for [ChannelCreated] is exact here too.
class ChannelUpdated extends ServerEvent {
  const ChannelUpdated(this.channel);

  final Channel channel;
}

/// A channel was soft-deleted. Gated on having been able to view it a moment
/// before, not on the ordinary current-permission check, which always
/// answers "no such channel" the instant this fires and so would reach
/// nobody.
class ChannelDeleted extends ServerEvent {
  const ChannelDeleted({required this.channelId});

  final String channelId;
}

/// A permission overwrite was set or cleared for one role or one member in
/// this channel. Never carries the allow/deny mask, the same privileged
/// detail [RoleChanged] withholds. A viewer who gains access from this exact
/// change is told; one it revokes is a known, narrow gap (see the server's
/// own notes on `http::ws::authorize`).
class OverwriteChanged extends ServerEvent {
  const OverwriteChanged({required this.channelId});

  final String channelId;
}

/// A channel category was created, renamed, repositioned, or deleted.
/// Carries no fields at all: a category is organisational only (see
/// docs/decisions/0006-channel-categories.md), so there is nothing
/// privileged to withhold and nothing per-viewer to resolve. A receiver
/// re-fetches `listChannels`, the same path [ChannelCreated],
/// [ChannelUpdated] and [ChannelDeleted] already drive.
class CategoryChanged extends ServerEvent {
  const CategoryChanged();
}

/// Someone's presence on a channel's voice call changed: a join, a clean
/// hangup, or the stale-heartbeat sweep evicting someone. Carries only the
/// channel id, never who - unlike [ThreadUpdated]'s reply count, a voice
/// roster is per-viewer (`listVoiceRoster` drops a hidden participant from
/// every viewer but themselves), so naming a joiner here would be a second,
/// unfiltered way to learn who is on a call. A receiver re-fetches the
/// roster, which already applies that filtering.
class VoiceActivityChanged extends ServerEvent {
  const VoiceActivityChanged({required this.channelId});

  final String channelId;
}
