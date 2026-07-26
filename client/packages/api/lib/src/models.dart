// SPDX-License-Identifier: Apache-2.0
/// Wire types, mirroring the schemas in `schema/openapi.yaml`.
///
/// These are hand-written rather than generated, but the shapes and field names
/// are the schema's; the contract test in `test/` asserts every model here has a
/// matching schema entry, so drift shows up as a failing test rather than a
/// runtime surprise.
library;

/// The server's identity and negotiated protocol version.
class Version {
  const Version({
    required this.name,
    required this.version,
    required this.protocol,
    this.pushEnabled,
  });

  final String name;
  final String version;
  final int protocol;

  /// Whether the server can deliver push notifications at all. Null on
  /// servers too old to report it, which is "unknown", not "no": warning
  /// someone off a server that actually has push would be worse than
  /// staying quiet.
  final bool? pushEnabled;

  factory Version.fromJson(Map<String, dynamic> json) => Version(
        name: json['name'] as String,
        version: json['version'] as String,
        protocol: json['protocol'] as int,
        pushEnabled: json['push_enabled'] as bool?,
      );
}

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
  });

  final String id;
  final String name;
  final String kind;
  final int createdAt;

  bool get isVoice => kind == 'voice';

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        createdAt: json['created_at'] as int,
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
}
