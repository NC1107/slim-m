// SPDX-License-Identifier: Apache-2.0
/// Writing to and reading from the local store.
library;

import 'package:drift/drift.dart';
import 'package:slimm_api/api.dart' as api;

import 'database.dart';

/// The local store's read and write surface.
///
/// Every write path in the app goes through here, which is what makes the two
/// delivery routes (live WebSocket push and REST catch-up) safe to interleave:
/// they can arrive in any order, repeat each other, or overlap, and the result
/// is the same.
class MessageStore {
  MessageStore(this.db);

  final SlimmDatabase db;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Watches a channel's messages, oldest first, as the UI renders them.
  /// Pending sends sort last because they have no server order yet.
  Stream<List<Message>> watchChannel(String channelId, {int limit = 200}) {
    final query = db.select(db.messages)
      ..where((m) => m.channelId.equals(channelId))
      ..orderBy([
        (m) => OrderingTerm(expression: m.seq),
        (m) => OrderingTerm(expression: m.createdAt),
      ])
      ..limit(limit);
    return query.watch();
  }

  Stream<List<Channel>> watchChannels() {
    final query = db.select(db.channels)
      ..orderBy([(c) => OrderingTerm(expression: c.createdAt)]);
    return query.watch();
  }

  /// The highest `seq` held for a channel: what catch-up should resume from.
  Future<int> cursorFor(String channelId) async {
    final row = await (db.select(db.channels)
          ..where((c) => c.id.equals(channelId)))
        .getSingleOrNull();
    return row?.cursor ?? 0;
  }

  /// Every channel's cursor, for a bundled catch-up request.
  Future<List<api.ScopeCursor>> allCursors() async {
    final rows = await db.select(db.channels).get();
    return rows
        .map((c) => api.ScopeCursor(channelId: c.id, afterSeq: c.cursor))
        .toList(growable: false);
  }

  /// Unread count for a channel, derived rather than stored so it cannot drift.
  Future<int> unreadCount(String channelId) async {
    final row = await (db.select(db.channels)
          ..where((c) => c.id.equals(channelId)))
        .getSingleOrNull();
    if (row == null) return 0;
    final count = countAll();
    final query = db.selectOnly(db.messages)
      ..addColumns([count])
      ..where(
        db.messages.channelId.equals(channelId) &
            db.messages.seq.isBiggerThanValue(row.lastReadSeq) &
            db.messages.pending.equals(false),
      );
    return await query.map((r) => r.read(count) ?? 0).getSingle();
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Replaces the known channel list, keeping each channel's local cursor and
  /// read marker, which the server's channel list does not carry.
  Future<void> upsertChannels(List<api.Channel> channels) async {
    await db.batch((batch) {
      for (final channel in channels) {
        batch.insert(
          db.channels,
          ChannelsCompanion.insert(
            id: channel.id,
            name: channel.name,
            kind: channel.kind,
            createdAt: channel.createdAt,
            topic: Value(channel.topic),
          ),
          onConflict: DoUpdate(
            (_) => ChannelsCompanion.custom(
              name: Variable(channel.name),
              kind: Variable(channel.kind),
              topic: Variable(channel.topic),
            ),
          ),
        );
      }
    });
  }

  /// Applies one message from the server, whichever route it arrived by.
  ///
  /// Idempotent and order-safe: re-applying the same message changes nothing,
  /// and an older version of a message can never overwrite a newer one. This is
  /// the single place those two rules live.
  Future<void> applyMessage(api.Message message) async {
    await db.transaction(() async {
      final existing = await (db.select(db.messages)
            ..where((m) => m.id.equals(message.id)))
          .getSingleOrNull();

      // A stale copy of something already stored: ignore it. Pending rows are
      // always replaced, since the server's version is authoritative.
      if (existing != null && !existing.pending && existing.seq > message.seq) {
        return;
      }

      await db.into(db.messages).insertOnConflictUpdate(
            MessagesCompanion.insert(
              id: message.id,
              channelId: message.channelId,
              authorId: Value(message.authorId),
              authorDisplayName: Value(message.authorDisplayName),
              seq: Value(message.seq),
              content: message.content,
              createdAt: message.createdAt,
              editedAt: Value(message.editedAt),
              pending: const Value(false),
              failed: const Value(false),
            ),
          );

      await _advanceCursor(message.channelId, message.seq);
    });
  }

  /// Applies a batch, for catch-up. One transaction so a partial apply cannot
  /// leave the cursor ahead of the messages it claims to cover.
  Future<void> applyMessages(Iterable<api.Message> messages) async {
    await db.transaction(() async {
      for (final message in messages) {
        await applyMessage(message);
      }
    });
  }

  /// Drops a channel's cached messages and rewinds its cursor. Used when the
  /// server answers catch-up with `reset`, meaning the gap was too large to
  /// stream and local state cannot be trusted.
  Future<void> resetChannel(String channelId) async {
    await db.transaction(() async {
      await (db.delete(db.messages)
            ..where(
                (m) => m.channelId.equals(channelId) & m.pending.equals(false)))
          .go();
      await (db.update(db.channels)..where((c) => c.id.equals(channelId)))
          .write(const ChannelsCompanion(cursor: Value(0)));
    });
  }

  /// Drops everything this device has cached: every channel, every message,
  /// every cursor and read marker, including pending sends.
  ///
  /// Unlike [resetChannel] this keeps nothing at all, because it is called when
  /// the cached data stops belonging to whoever is about to use the app: a sign
  /// out, an account deletion, or a switch to a different server. A pending
  /// send is the previous account's unsent message and must go with the rest,
  /// which is exactly why this cannot be built out of [resetChannel].
  Future<void> clear() async {
    await db.transaction(() async {
      await db.delete(db.messages).go();
      await db.delete(db.channels).go();
    });
  }

  /// Records a message the user just sent, before the server has seen it, so it
  /// appears immediately. Replaced in place by [applyMessage] on acknowledgement
  /// because both are keyed by the same client-generated id.
  Future<void> addPending({
    required String id,
    required String channelId,
    required String authorId,
    required String content,
  }) async {
    await db.into(db.messages).insertOnConflictUpdate(
          MessagesCompanion.insert(
            id: id,
            channelId: channelId,
            authorId: Value(authorId),
            content: content,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            pending: const Value(true),
            failed: const Value(false),
          ),
        );
  }

  /// Marks a pending send as failed so the UI can offer a retry. The row is kept
  /// rather than dropped, so the user does not silently lose what they typed.
  Future<void> markFailed(String id) async {
    await (db.update(db.messages)..where((m) => m.id.equals(id))).write(
        const MessagesCompanion(pending: Value(false), failed: Value(true)));
  }

  /// Discards a pending or failed message the user chose not to keep.
  Future<void> discard(String id) async {
    await (db.delete(db.messages)..where((m) => m.id.equals(id))).go();
  }

  /// Mirrors the server's read marker.
  Future<void> setReadMarker(String channelId, int seq) async {
    await db.transaction(() async {
      final row = await (db.select(db.channels)
            ..where((c) => c.id.equals(channelId)))
          .getSingleOrNull();
      if (row == null || row.lastReadSeq >= seq) return;
      await (db.update(db.channels)..where((c) => c.id.equals(channelId)))
          .write(ChannelsCompanion(lastReadSeq: Value(seq)));
    });
  }

  /// Moves a channel's cursor forward. Never backwards: the cursor is the
  /// high-water mark of what has been applied.
  Future<void> _advanceCursor(String channelId, int seq) async {
    final row = await (db.select(db.channels)
          ..where((c) => c.id.equals(channelId)))
        .getSingleOrNull();
    if (row == null || row.cursor >= seq) return;
    await (db.update(db.channels)..where((c) => c.id.equals(channelId)))
        .write(ChannelsCompanion(cursor: Value(seq)));
  }
}
