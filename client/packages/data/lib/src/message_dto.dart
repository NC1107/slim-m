// SPDX-License-Identifier: Apache-2.0
/// The plain value type everything outside this package sees for a locally
/// cached message.
///
/// This is a boundary DTO, not an incidental alias for the drift row: no
/// drift import, no `Insertable`, no `Companion`, nothing from
/// `package:drift/drift.dart` anywhere in this file. `database.dart`'s
/// `MessageRowMapping.toDto` is the only place a drift `MessageRow` becomes
/// one of these, and `MessageStore` is the only caller of it, so a drift
/// type never has to cross into `app` or any other package.
///
/// Every field here mirrors a `messages` column today because `app` reads
/// every one of them somewhere (message actions, the transcript, the reply
/// banner, the composer). That is a fact about what `app` currently needs,
/// not a promise that a future storage-only column drift adds must appear
/// here too - see `docs/decisions/` for the storage-layer boundary this DTO
/// exists to hold.
///
/// Equality and hashing are over every field, matching the drift `DataClass`
/// this replaces: nothing in `app` is known to key a `Set`/`Map` or drive a
/// `riverpod` `select` off a whole `Message` today, but a plain identity
/// default (`==` falling back to `identical`) would be a silent behaviour
/// change for the first caller that ever does, so value equality is kept.
library;

/// One locally cached message, independent of how it is stored.
class Message {
  const Message({
    required this.id,
    required this.channelId,
    this.authorId,
    this.authorDisplayName,
    required this.seq,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.replyToId,
    required this.pending,
    required this.failed,
    this.failureReason,
  });

  final String id;
  final String channelId;
  final String? authorId;

  /// Sent with the message so rendering a channel needs no lookup per
  /// sender. Null when the author was anonymized, exactly as [authorId] is.
  final String? authorDisplayName;

  /// Server order key. Zero while a message is only local (an optimistic
  /// echo that has not been acknowledged yet), so pending messages sort
  /// last.
  final int seq;
  final String content;
  final int createdAt;
  final int? editedAt;

  /// The message this one replies to, or null. Only ever the id - see
  /// `Messages.replyToId` in `database.dart` for why nothing else about the
  /// parent is copied onto this row.
  final String? replyToId;

  /// True while the send is in flight. The UI shows these differently and
  /// they are replaced in place by the server's copy on acknowledgement.
  final bool pending;

  /// True when the send failed and the user can retry it.
  final bool failed;

  /// Why [failed] is true, in the server's own words. Null whenever
  /// [failed] is false.
  final String? failureReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == id &&
          other.channelId == channelId &&
          other.authorId == authorId &&
          other.authorDisplayName == authorDisplayName &&
          other.seq == seq &&
          other.content == content &&
          other.createdAt == createdAt &&
          other.editedAt == editedAt &&
          other.replyToId == replyToId &&
          other.pending == pending &&
          other.failed == failed &&
          other.failureReason == failureReason);

  @override
  int get hashCode => Object.hash(
        id,
        channelId,
        authorId,
        authorDisplayName,
        seq,
        content,
        createdAt,
        editedAt,
        replyToId,
        pending,
        failed,
        failureReason,
      );
}
