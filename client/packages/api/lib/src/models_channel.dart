// SPDX-License-Identifier: Apache-2.0
/// The `Channel` wire model, split out of `models.dart` for the line budget.
library;

/// A text or voice channel.
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.topic,
    this.position = 0,
    this.isPersonalSpace = false,
    this.dmParticipantId,
    this.parentMessageId,
    this.categoryId,
  });

  final String id;
  final String name;
  final String kind;
  final int createdAt;

  /// A one-line header shown beside the name. Null for no topic; the server
  /// never stores an empty string, so blank and absent mean the same thing.
  final String? topic;

  /// Sort key among the deployment's live, non-DM channels: lower sorts
  /// first. Deployment-wide, set by [SlimmApiChannelAdmin.reorderChannels],
  /// not a per-device preference. Defaults to 0 for a server too old to send
  /// it, which reads as "unordered" rather than a real position - the same
  /// reason a missing `topic` reads as unknown rather than "no topic".
  /// Meaningless on a DM, which never appears in [SlimmApi.listChannels].
  final int position;

  /// Whether this row is the caller's own personal space: a DM with
  /// themself. Never sent or read on the wire - the server has no such
  /// concept, and [fromJson] always defaults this to false - it is set only
  /// by `channelFromDm` (`providers/dms.dart`), the one place a caller's id
  /// is compared against the DM's other participant. [name] is cosmetic
  /// display copy and must never be used to answer this question: another
  /// member's freely chosen display name can collide with it.
  final bool isPersonalSpace;

  /// The other user in this DM, or null for a non-DM channel. Never sent or
  /// read on the wire, exactly like [isPersonalSpace] and set at the same
  /// place, so a caller that needs to know who a DM is with (blocking) can
  /// read it off the local row instead of fetching the whole `/dms` listing.
  final String? dmParticipantId;

  /// The message this channel is a thread of, or null for an ordinary
  /// channel. A thread's `VIEW_CHANNEL`/`SEND_MESSAGES` inherit the parent
  /// message's own channel, resolved server-side rather than copied; a
  /// thread never appears in [SlimmApi.listChannels] - reach one through
  /// [SlimmApiThreads.openThread] or a message's own `threadChannelId`.
  final String? parentMessageId;

  /// The rail section this channel is filed under, or null for
  /// uncategorised - rendered as an implicit section above every named
  /// category. Decides placement only, never behaviour: see
  /// docs/decisions/0006-channel-categories.md. Absent on a server too old
  /// to send it, which reads the same as uncategorised on this client, since
  /// there is nothing older to distinguish it from.
  final String? categoryId;

  bool get isVoice => kind == 'voice';

  /// Whether this row is a thread rather than an ordinary channel - see
  /// [parentMessageId].
  bool get isThread => parentMessageId != null;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        createdAt: json['created_at'] as int,
        topic: json['topic'] as String?,
        position: json['position'] as int? ?? 0,
        parentMessageId: json['parent_message_id'] as String?,
        categoryId: json['category_id'] as String?,
      );
}

/// A rail section a channel of any kind may be filed under. Carries no
/// permission of its own - see docs/decisions/0006-channel-categories.md.
class ChannelCategory {
  const ChannelCategory({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Sort key among the deployment's live categories: lower sorts first.
  final int position;
  final int createdAt;

  factory ChannelCategory.fromJson(Map<String, dynamic> json) =>
      ChannelCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        position: json['position'] as int,
        createdAt: json['created_at'] as int,
      );
}

/// One rail section's ordered contents, as a drag produces: the category it
/// names (null for the implicit uncategorised section) and every channel now
/// filed under it, in display order. The request shape
/// [SlimmApiChannelAdmin.reorderChannels] sends.
class ChannelOrderGroup {
  const ChannelOrderGroup({required this.categoryId, required this.channelIds});

  final String? categoryId;
  final List<String> channelIds;

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'channel_ids': channelIds,
      };
}
