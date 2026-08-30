// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests the schema-3 migration, which exists to repair a cache that could not
/// repair itself.
///
/// Schema 2 added the author's display name and left existing rows null,
/// expecting the next sync to replace them. Sync is keyset on `seq` and only
/// asks for messages newer than the channel cursor, so nothing ever did: on a
/// real client 19 of 22 messages were stuck rendering as an unknown author.
/// The migration drops the cached messages and rewinds the cursor so a catch-up
/// refills them, and this asserts both halves, because rewinding without
/// dropping leaves duplicates and dropping without rewinding loses the history
/// outright.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

/// Builds the schema exactly as version 2 left it: a display-name column that
/// exists and is null, and a channel whose cursor has advanced past the
/// messages already held.
Future<void> _seedSchemaV2(File file) async {
  final db = NativeDatabase(file);
  final executor = DatabaseConnection(db);
  Future<void> run(String sql) => executor.executor.runCustom(sql, const []);

  await executor.executor.ensureOpen(_NoopUser());
  await run('CREATE TABLE channels (id TEXT NOT NULL PRIMARY KEY, '
      'name TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL, '
      'cursor INTEGER NOT NULL DEFAULT 0, '
      'last_read_seq INTEGER NOT NULL DEFAULT 0)');
  await run('CREATE TABLE messages (id TEXT NOT NULL PRIMARY KEY, '
      'channel_id TEXT NOT NULL, author_id TEXT, author_display_name TEXT, '
      'seq INTEGER NOT NULL, content TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, edited_at INTEGER, '
      'pending INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0)');
  await run("INSERT INTO channels "
      "(id, name, kind, created_at, cursor, last_read_seq) "
      "VALUES ('chan-1', 'general', 'text', 900, 22, 3)");
  await run("INSERT INTO messages "
      "(id, channel_id, author_id, author_display_name, seq, content, "
      "created_at, edited_at, pending, failed) VALUES "
      "('m-1', 'chan-1', 'user-1', NULL, 1, 'stuck as unknown', 1000, "
      "NULL, 0, 0)");
  await run('PRAGMA user_version = 2');
  await executor.executor.close();
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails details) async {}
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('slimm-migration');
    file = File('${dir.path}/slimm.sqlite');
    await _seedSchemaV2(file);
  });

  tearDown(() => dir.delete(recursive: true));

  test('a message stranded without an author name does not survive the upgrade',
      () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final rows = await db.select(db.messages).get();

    // Not "the name is filled in": the client cannot fill it in locally. The
    // row goes, so the next sync refetches the copy that has the name.
    expect(rows, isEmpty);
  });

  test('the cursor rewinds, or the dropped messages are never fetched again',
      () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();

    expect(channel.cursor, 0, reason: 'sync asks only for seq > cursor');
  });

  test('the channel itself survives, along with where the user had read to',
      () async {
    // Dropping the channel would sign the user out of their own sidebar and
    // mark everything unread; only the message cache is disposable.
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();

    expect(channel.id, 'chan-1');
    expect(channel.name, 'general');
    expect(channel.lastReadSeq, 3);
  });
}
