// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
export 'models_forwards.dart';
export 'models_gifs.dart';
export 'models_identity.dart';
export 'models_moderation.dart';
export 'models_moderation_history.dart';
export 'models_canvas.dart';
export 'models_canvas_ops.dart';
export 'models_channel.dart';
export 'models_channel_notification_override.dart';
export 'models_message_history.dart';
export 'models_message_ops.dart';
export 'models_notification_preference.dart';
export 'models_pins.dart';
export 'models_polls.dart';
export 'models_presence.dart';
export 'models_quiet_hours.dart';
export 'models_reactions.dart';
export 'models_roles.dart';
export 'models_saved.dart';
export 'models_users.dart';
export 'models_version.dart';

// Message needs these in scope here, which only `import` grants; the exports
// above are what re-surface them to callers of this file.
import 'models_attachments.dart';
import 'models_forwards.dart';
import 'models_message_ops.dart';
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
    this.replyToId,
    this.threadChannelId,
    this.threadReplyCount,
    this.threadLastReplyAt,
    this.threadUnreadCount,
    // Empty is the honest default and the common case; requiring these at
    // every construction site bought no safety and broke every caller.
    this.reactions = const [],
    this.attachments = const [],
    this.poll,
    this.forwarded,
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

  /// The message this one replies to, or null. Only ever the id: resolve the
  /// parent's own content, author and liveness by looking that id up locally
  /// like any other message, never trust a cached copy of them here - there
  /// is none, on purpose, so a later edit or delete of the parent is never
  /// something this row could go stale about.
  final String? replyToId;

  /// The thread opened from this message, or null if none has been started
  /// yet. Open (or reuse) it with [SlimmApiThreads.openThread].
  final String? threadChannelId;

  /// Undeleted replies in this message's thread, or null exactly when
  /// [threadChannelId] is null. Can be zero: opening a thread creates its
  /// channel before the first reply lands in it, so a caller rendering a
  /// reply-count affordance must check for a positive count, not merely a
  /// non-null [threadChannelId].
  final int? threadReplyCount;

  /// When the thread's newest undeleted reply was sent, unix milliseconds,
  /// or null when [threadReplyCount] is null or zero.
  final int? threadLastReplyAt;

  /// How many of the thread's live messages the caller has not yet read, or
  /// null exactly when [threadChannelId] is null - same convention as the
  /// other two thread fields. Genuinely 0 for a thread the caller has fully
  /// read, never omitted the way an unstarted thread's fields are.
  final int? threadUnreadCount;

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

  /// What this message forwards, or null when it forwards nothing.
  ///
  /// [content] is the sender's own note alongside it and is often empty; the
  /// thing being forwarded is in here and is never mixed into that text.
  final ForwardedMessage? forwarded;

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
        replyToId: json['reply_to_id'] as String?,
        threadChannelId: json['thread_channel_id'] as String?,
        threadReplyCount: json['thread_reply_count'] as int?,
        threadLastReplyAt: json['thread_last_reply_at'] as int?,
        threadUnreadCount: json['thread_unread_count'] as int?,
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
        forwarded: json['forwarded'] == null
            ? null
            : ForwardedMessage.fromJson(
                json['forwarded'] as Map<String, dynamic>),
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

/// A DM call ring the caller just started, from `POST
/// /channels/{id}/voice/ring`.
class RingStarted {
  const RingStarted({required this.ringId, required this.timeoutMs});

  final String ringId;

  /// How long the server itself waits for an answer before giving up on this
  /// ring; a client renders its own countdown from this rather than a
  /// hard-coded duration that could drift from the server's.
  final int timeoutMs;

  factory RingStarted.fromJson(Map<String, dynamic> json) => RingStarted(
        ringId: json['ring_id'] as String,
        timeoutMs: json['timeout_ms'] as int,
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
  const ScopeCursor({
    required this.channelId,
    required this.afterSeq,
    this.afterOpSeq,
  });

  final String channelId;
  final int afterSeq;

  /// The message-op cursor, absent when this client holds none.
  ///
  /// Absent is what an older client always sends and what a newer one sends
  /// before it has adopted a head, and both get the same answer: no ops, and
  /// never a reset from an op gap. Sending it is what opts a scope in.
  final int? afterOpSeq;

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'after_seq': afterSeq,
        if (afterOpSeq != null) 'after_op_seq': afterOpSeq,
      };
}

/// What catch-up returned for one scope.
class ScopeDelta {
  const ScopeDelta({
    required this.channelId,
    required this.messages,
    required this.hasMore,
    required this.reset,
    this.ops = const <MessageOp>[],
    this.opLatestSeq,
    this.opsHasMore = false,
  });

  final String channelId;

  /// Oldest first, unlike history, which is newest first.
  final List<Message> messages;

  /// More remains past what this response carried.
  final bool hasMore;

  /// Either cursor was too far behind: drop local state for this scope and
  /// refetch. There is no separate ops flag, because the recovery is the same
  /// either way, and it is only ever set from an op gap for a scope whose
  /// request carried an op cursor.
  final bool reset;

  /// Empty whenever the request carried no op cursor, and empty when there is
  /// genuinely nothing, the convention `reactions` and `attachments` follow.
  final List<MessageOp> ops;

  /// The head of the channel's op stream, and the old-server detector: a
  /// server with no op stream sends no such key, so null means "this
  /// deployment cannot reconcile" rather than "the stream is empty".
  ///
  /// Detection is by field absence rather than through the capability
  /// handshake, which derives its list by probing the router and so can see a
  /// new path but never a new field.
  final int? opLatestSeq;

  /// More ops remain past what this response carried.
  final bool opsHasMore;

  factory ScopeDelta.fromJson(Map<String, dynamic> json) => ScopeDelta(
        channelId: json['channel_id'] as String,
        messages: (json['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(growable: false),
        hasMore: json['has_more'] as bool,
        reset: json['reset'] as bool,
        ops: (json['ops'] as List<dynamic>? ?? const <dynamic>[])
            .map((o) => MessageOp.fromJson(o as Map<String, dynamic>))
            .toList(growable: false),
        opLatestSeq: json['op_latest_seq'] as int?,
        opsHasMore: json['ops_has_more'] as bool? ?? false,
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

/// The caller's own private note about another account. Caller-private,
/// always: this is never the subject's own view of anything, only what the
/// caller themselves wrote down about them.
///
/// `body` and `updatedAt` are both null together, meaning the caller has
/// left no note about that subject - the same all-null shape a fresh account
/// gets, so this cannot be used to tell "no note yet" apart from anything
/// else about the subject.
class UserNote {
  const UserNote({required this.body, required this.updatedAt});

  final String? body;
  final int? updatedAt;

  factory UserNote.fromJson(Map<String, dynamic> json) => UserNote(
        body: json['body'] as String?,
        updatedAt: json['updated_at'] as int?,
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
