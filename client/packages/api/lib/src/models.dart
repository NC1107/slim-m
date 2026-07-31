// SPDX-License-Identifier: Apache-2.0
/// Wire types, mirroring the schemas in `schema/openapi.yaml`.
///
/// Hand-written rather than generated, and deliberately so: nothing here is
/// checked against the schema by any test. The route surface is gated
/// (`crates/slimm-server/tests/openapi_contract.rs`), but field names,
/// nullability, and status codes are not, on any of the three sides. A field
/// renamed on the server and not here fails at runtime, as a null where a value
/// was expected, so treat the schema as the record and change both together.
library;

// Split for the line budget; each is exported here so importing this one file
// still surfaces every model, as if they had all been written in one place.
export 'models_admin.dart';
export 'models_attachments.dart';
export 'models_dms.dart';
export 'models_emoji.dart';
export 'models_identity.dart';
export 'models_moderation.dart';
export 'models_canvas.dart';
export 'models_canvas_ops.dart';
export 'models_pins.dart';
export 'models_polls.dart';
export 'models_presence.dart';
export 'models_reactions.dart';
export 'models_roles.dart';
export 'models_users.dart';
export 'models_version.dart';

// Message needs these in scope here, which only `import` grants; the exports
// above are what re-surface them to callers of this file.
import 'models_attachments.dart';
import 'models_polls.dart';
import 'models_reactions.dart';

/// A session's credentials. The tokens are secrets: never log this.
class TokenPair {
  const TokenPair({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;

  /// Unix milliseconds at which [accessToken] stops working.
  final int accessExpiresAt;

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        userId: json['user_id'] as String,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        accessExpiresAt: json['access_expires_at'] as int,
      );

  /// For persisting the session locally, in a platform key store rather than
  /// a log or anywhere else these secrets could linger in plain text.
  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'access_expires_at': accessExpiresAt,
      };

  /// Deliberately hides the secrets, so an accidental interpolation into a log
  /// cannot leak a working credential.
  @override
  String toString() =>
      'TokenPair(userId: $userId, expiresAt: $accessExpiresAt)';
}

/// A single-use ticket that opens a WebSocket.
class Ticket {
  const Ticket({required this.ticket, required this.expiresAt});

  final String ticket;
  final int expiresAt;

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
      ticket: json['ticket'] as String, expiresAt: json['expires_at'] as int);

  @override
  String toString() => 'Ticket(expiresAt: $expiresAt)';
}

/// A text or voice channel.
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.topic,
    this.isPersonalSpace = false,
    this.dmParticipantId,
  });

  final String id;
  final String name;
  final String kind;
  final int createdAt;

  /// A one-line header shown beside the name. Null for no topic; the server
  /// never stores an empty string, so blank and absent mean the same thing.
  final String? topic;

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

  bool get isVoice => kind == 'voice';

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        createdAt: json['created_at'] as int,
        topic: json['topic'] as String?,
      );
}

/// A message. [id] is the client-generated identity and idempotency key; [seq]
/// is the server's per-channel order key and the sync cursor. They are separate
/// on purpose and must not be conflated.
class Message {
  const Message({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.authorDisplayName,
    required this.seq,
    required this.content,
    required this.createdAt,
    required this.editedAt,
    // Empty is the honest default and the common case; requiring these at
    // every construction site bought no safety and broke every caller.
    this.reactions = const [],
    this.attachments = const [],
    this.poll,
  });

  final String id;
  final String channelId;

  /// Null once the author's account has been deleted.
  final String? authorId;

  /// The author's display name, sent with the message so a channel does not
  /// need a lookup per distinct sender. Null for the same reason [authorId]
  /// is: the account was anonymized and there is no name left to show.
  final String? authorDisplayName;
  final int seq;
  final String content;
  final int createdAt;
  final int? editedAt;

  /// Reaction summaries, one entry per distinct emoji, with `reacted` set
  /// from the calling user's point of view. Always present: an empty list
  /// means no reactions, never that the server omitted them.
  final List<ReactionSummary> reactions;

  /// The poll this message carries, if it is a poll message. Null both for an
  /// ordinary message and for a key the server omitted, so an older server
  /// that never heard of polls parses identically to one that just has none
  /// here.
  final Poll? poll;

  /// Attachments riding on this message, in display order. Always present:
  /// an empty list means none, never that the server omitted them. Unlike
  /// [reactions] and [poll], a freshly sent message can carry these
  /// immediately, since they are uploaded before the send and only
  /// referenced by it.
  final List<Attachment> attachments;

  bool get isEdited => editedAt != null;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        channelId: json['channel_id'] as String,
        authorId: json['author_id'] as String?,
        authorDisplayName: json['author_display_name'] as String?,
        seq: json['seq'] as int,
        content: json['content'] as String,
        createdAt: json['created_at'] as int,
        editedAt: json['edited_at'] as int?,
        // Not in the schema's `required` list despite its description promising
        // it is always sent; empty beats crashing on a conformant response.
        reactions: (json['reactions'] as List<dynamic>?)
                ?.map(
                    (r) => ReactionSummary.fromJson(r as Map<String, dynamic>))
                .toList(growable: false) ??
            const [],
        poll: json['poll'] == null
            ? null
            : Poll.fromJson(json['poll'] as Map<String, dynamic>),
        attachments: (json['attachments'] as List<dynamic>?)
                ?.map((a) => Attachment.fromJson(a as Map<String, dynamic>))
                .toList(growable: false) ??
            const [],
      );
}

/// A short-lived credential for a channel's voice room.
///
/// [canPublish] mirrors the SPEAK grant inside the token, so the UI can show a
/// listen-only state up front rather than after the SFU refuses a track.
class VoiceToken {
  const VoiceToken({
    required this.url,
    required this.room,
    required this.token,
    required this.expiresAt,
    required this.canPublish,
  });

  final String url;
  final String room;
  final String token;
  final int expiresAt;
  final bool canPublish;

  factory VoiceToken.fromJson(Map<String, dynamic> json) => VoiceToken(
        url: json['url'] as String,
        room: json['room'] as String,
        token: json['token'] as String,
        expiresAt: json['expires_at'] as int,
        canPublish: json['can_publish'] as bool,
      );
}

/// One participant the server reports as currently connected to a channel's
/// voice room, from `GET /channels/{id}/voice/roster`.
///
/// [displayName] is as it was when this participant joined, not necessarily
/// their current profile name; a participant who chose to appear offline is
/// never sent to any viewer but themselves, so absence from the list is not
/// distinguishable from never having joined.
class VoiceRosterParticipant {
  const VoiceRosterParticipant(
      {required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  factory VoiceRosterParticipant.fromJson(Map<String, dynamic> json) =>
      VoiceRosterParticipant(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
      );
}

/// How far a user has read in a channel, and how much is left.
class ReadState {
  const ReadState({required this.lastReadSeq, required this.unread});

  final int lastReadSeq;
  final int unread;

  factory ReadState.fromJson(Map<String, dynamic> json) => ReadState(
        lastReadSeq: json['last_read_seq'] as int,
        unread: json['unread'] as int,
      );
}

/// One scope's position, sent when catching up.
class ScopeCursor {
  const ScopeCursor({required this.channelId, required this.afterSeq});

  final String channelId;
  final int afterSeq;

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'after_seq': afterSeq,
      };
}

/// What catch-up returned for one scope.
class ScopeDelta {
  const ScopeDelta({
    required this.channelId,
    required this.messages,
    required this.hasMore,
    required this.reset,
  });

  final String channelId;

  /// Oldest first, unlike history, which is newest first.
  final List<Message> messages;

  /// More remains past what this response carried.
  final bool hasMore;

  /// The cursor was too far behind: drop local state for this scope and refetch.
  final bool reset;

  factory ScopeDelta.fromJson(Map<String, dynamic> json) => ScopeDelta(
        channelId: json['channel_id'] as String,
        messages: (json['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(growable: false),
        hasMore: json['has_more'] as bool,
        reset: json['reset'] as bool,
      );
}

/// A device signed in to the account.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  final String id;
  final String name;
  final int createdAt;
  final int? lastSeenAt;

  /// True for the device making the request, so the UI can label it and warn
  /// before someone signs themselves out.
  final bool isCurrent;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: json['created_at'] as int,
        lastSeenAt: json['last_seen_at'] as int?,
        isCurrent: json['is_current'] as bool,
      );
}

/// What a report is about.
enum ReportSubject {
  message,
  user;

  String get wire => name;

  /// An unrecognised value reads as [user]: it is the more generic subject,
  /// so a future kind this client has never heard of does not get rendered
  /// as reported message content - an author and a snapshot - that may not
  /// exist for whatever that new kind turns out to be.
  static ReportSubject parse(String value) => switch (value) {
        'message' => ReportSubject.message,
        _ => ReportSubject.user,
      };
}
