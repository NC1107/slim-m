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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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
