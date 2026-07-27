// SPDX-License-Identifier: Apache-2.0
/// The local database: the client's single source of truth.
///
/// The UI reads only from here, never from the network directly. Anything that
/// arrives, whether pushed over the WebSocket or pulled by catch-up, is written
/// here first and then observed, so both paths converge on the same state and
/// there is one place where ordering and de-duplication are decided.
///
/// Two rules make that safe, and both are enforced in [applyMessage]:
///
/// - Identity is the server's message id (a UUIDv7). Writes are upserts keyed by
///   it, so the same message arriving twice, once live and once from catch-up,
///   is stored once.
/// - Order is the per-channel `seq`. A row is only overwritten by something with
///   a `seq` at least as high, so a late-arriving duplicate of an older state
///   can never clobber a newer one.
library;

import 'package:drift/drift.dart';

part 'database.g.dart';

/// Locally cached channels.
class Channels extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  IntColumn get createdAt => integer()();

  /// A one-line header shown beside the name. Null for no topic.
  TextColumn get topic => text().nullable()();

  /// The highest `seq` this client holds for the channel: the sync cursor.
  IntColumn get cursor => integer().withDefault(const Constant(0))();

  /// How far the user has read, mirrored from the server.
  IntColumn get lastReadSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Locally cached messages.
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get channelId => text()();
  TextColumn get authorId => text().nullable()();

  /// Sent with the message so rendering a channel needs no lookup per sender.
  /// Null when the author was anonymized, exactly as [authorId] is.
  TextColumn get authorDisplayName => text().nullable()();

  /// Server order key. Zero while a message is only local (an optimistic echo
  /// that has not been acknowledged yet), so pending messages sort last.
  IntColumn get seq => integer().withDefault(const Constant(0))();
  TextColumn get content => text()();
  IntColumn get createdAt => integer()();
  IntColumn get editedAt => integer().nullable()();

  /// True while the send is in flight. The UI shows these differently and they
  /// are replaced in place by the server's copy on acknowledgement.
  BoolColumn get pending => boolean().withDefault(const Constant(false))();

  /// True when the send failed and the user can retry it.
  BoolColumn get failed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Channels, Messages])
class SlimmDatabase extends _$SlimmDatabase {
  SlimmDatabase(super.e);

  @override
  int get schemaVersion => 4;

  /// How each schema version is reached, and why v3 throws the cache away.
  ///
  /// v2 added the author's display name and left existing rows null, on the
  /// assumption that the next sync would replace them. It does not: sync is
  /// keyset on `seq` and only ever asks for messages newer than the cursor, so
  /// every message that predated the upgrade kept a null name permanently and
  /// rendered as an unknown author. On a real client that was 19 of 22
  /// messages.
  ///
  /// v3 drops the message cache and rewinds the cursor, and that is the whole
  /// fix. This table is a cache of server state with no local-only rows worth
  /// keeping, so the cost is one catch-up sync and the benefit is that the
  /// client cannot be left holding a version of a message the server has a
  /// better copy of.
  ///
  /// v4 adds `channels.topic` in place instead. Unlike the message cache,
  /// channels are fully refetched on every sync rather than paged by a cursor,
  /// so a null topic fills itself in on the next connect without dropping
  /// anything.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(messages, messages.authorDisplayName);
          }
          // Channels are refetched whole on every sync, so this column can be
          // added in place. See the doc comment above.
          if (from < 4) {
            await m.addColumn(channels, channels.topic);
          }
          // v2's null display names are unreachable by a keyset sync, so the
          // cache is dropped and the cursor rewound. See the doc comment above.
          if (from < 3) {
            await m.deleteTable(messages.actualTableName);
            await m.createTable(messages);
            await m.database.customStatement('UPDATE channels SET cursor = 0');
          }
        },
        beforeOpen: (details) async {
          // Keyset reads and unread counts both scan a channel newest-first, so the
          // index has to match that order to be used.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS messages_channel_seq '
            'ON messages (channel_id, seq DESC)',
          );
        },
      );
}
