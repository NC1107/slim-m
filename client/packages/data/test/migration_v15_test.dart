// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests the schema-15 migration, which is what an upgrading client needs to
/// hold a channel's own slow-mode interval.
///
/// Adds in place and loses nothing, the same shape v14's `mentionedSeq` took:
/// every existing row defaults to 0 (off), and the next channel refresh
/// replaces it with the server's real value, since channels are refetched
/// whole rather than paged by a cursor. Every other suite opens a fresh
/// version-15 database directly, so without this an upgrade whose body
/// silently did nothing would leave `schemaVersion` at 15 with no
/// `slow_mode_seconds` column at all, and nothing would notice until a real
/// client's local database was already stuck that way.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

/// Builds the schema exactly as version 14 left it: every column through
/// v14 (mentionedSeq included), and no `slow_mode_seconds` column at all.
Future<void> _seedSchemaV14(File file) async {
  final db = NativeDatabase(file);
  final executor = DatabaseConnection(db);
  Future<void> run(String sql) => executor.executor.runCustom(sql, const []);

  await executor.executor.ensureOpen(_NoopUser());
  await run('CREATE TABLE channels (id TEXT NOT NULL PRIMARY KEY, '
      'name TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL, '
      'topic TEXT, cursor INTEGER NOT NULL DEFAULT 0, '
      'last_read_seq INTEGER NOT NULL DEFAULT 0, '
      'mentioned_seq INTEGER NOT NULL DEFAULT 0, '
      'is_personal_space INTEGER NOT NULL DEFAULT 0, '
      'dm_participant_id TEXT, position INTEGER NOT NULL DEFAULT 0, '
      'op_cursor INTEGER, parent_message_id TEXT, category_id TEXT)');
  await run('CREATE TABLE channel_categories (id TEXT NOT NULL PRIMARY KEY, '
      'name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0)');
  await run('CREATE TABLE messages (id TEXT NOT NULL PRIMARY KEY, '
      'channel_id TEXT NOT NULL, author_id TEXT, author_display_name TEXT, '
      'seq INTEGER NOT NULL DEFAULT 0, content TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, edited_at INTEGER, '
      'reply_to_id TEXT, '
      'pending INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0, '
      'failure_reason TEXT)');
  await run("INSERT INTO channels "
      "(id, name, kind, created_at, topic, cursor, last_read_seq, "
      "mentioned_seq, is_personal_space, dm_participant_id, position, "
      "op_cursor, parent_message_id, category_id) "
      "VALUES ('chan-1', 'general', 'text', 900, 'topic here', 22, 3, 0, 0, "
      "NULL, 5, 10, NULL, NULL)");
  await run("INSERT INTO messages "
      "(id, channel_id, author_id, author_display_name, seq, content, "
      "created_at, edited_at, reply_to_id, pending, failed, failure_reason) "
      "VALUES ('m-1', 'chan-1', 'user-1', 'Mara', 1, 'hello', 1000, NULL, "
      "NULL, 0, 0, NULL)");
  await run('PRAGMA user_version = 14');
  await executor.executor.close();
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 14;

  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails details) async {}
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('slimm-migration-v15');
    file = File('${dir.path}/slimm.sqlite');
    await _seedSchemaV14(file);
  });

  tearDown(() => dir.delete(recursive: true));

  test('an upgrading client gains a real channels.slowModeSeconds column',
      () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Raw sqlite schema, not drift's row mapping: a missing column would read as null with no error.
    final columns = await db.customSelect('PRAGMA table_info(channels)').get();
    final names = columns.map((r) => r.read<String>('name')).toSet();

    expect(names, contains('slow_mode_seconds'));
  });

  test('an existing channel defaults to slow mode off', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();

    expect(
      channel.slowModeSeconds,
      0,
      reason: 'nothing to backfill it from; the next channel refresh fills '
          'in the server\'s real value',
    );
  });

  test('the existing channel and message rows survive the upgrade intact',
      () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();
    final message = await db.select(db.messages).getSingle();

    expect(channel.name, 'general');
    expect(channel.cursor, 22);
    expect(channel.opCursor, 10);
    expect(message.id, 'm-1');
    expect(message.content, 'hello');
  });
}
