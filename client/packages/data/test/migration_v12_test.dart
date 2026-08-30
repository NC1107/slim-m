// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests the schema-12 migration, which is what an upgrading client needs
/// for channel categories - see docs/decisions/0006-channel-categories.md.
///
/// Unlike v3's and v7's wipes, this one is meant to add in place and lose
/// nothing: `channels.categoryId` is new on both sides in the same release
/// (nothing existing could ever need backfilling into it), and
/// `channel_categories` is a fresh, empty table the next channel refresh
/// populates. Neither half is exercised by any other test - every other
/// suite opens a fresh version-12 database directly, so an upgrade that
/// silently skipped its own body would leave `schemaVersion` at 12 with
/// neither the column nor the table actually created, and nothing would
/// notice until a real client's local database was already stuck that way.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

/// Builds the schema exactly as version 11 left it: every column through
/// v11, and no `category_id` column or `channel_categories` table at all.
Future<void> _seedSchemaV11(File file) async {
  final db = NativeDatabase(file);
  final executor = DatabaseConnection(db);
  Future<void> run(String sql) => executor.executor.runCustom(sql, const []);

  await executor.executor.ensureOpen(_NoopUser());
  await run('CREATE TABLE channels (id TEXT NOT NULL PRIMARY KEY, '
      'name TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL, '
      'topic TEXT, cursor INTEGER NOT NULL DEFAULT 0, '
      'last_read_seq INTEGER NOT NULL DEFAULT 0, '
      'is_personal_space INTEGER NOT NULL DEFAULT 0, '
      'dm_participant_id TEXT, position INTEGER NOT NULL DEFAULT 0, '
      'op_cursor INTEGER, parent_message_id TEXT)');
  await run('CREATE TABLE messages (id TEXT NOT NULL PRIMARY KEY, '
      'channel_id TEXT NOT NULL, author_id TEXT, author_display_name TEXT, '
      'seq INTEGER NOT NULL DEFAULT 0, content TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, edited_at INTEGER, '
      'reply_to_id TEXT, '
      'pending INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0, '
      'failure_reason TEXT)');
  await run("INSERT INTO channels "
      "(id, name, kind, created_at, topic, cursor, last_read_seq, "
      "is_personal_space, dm_participant_id, position, op_cursor, "
      "parent_message_id) "
      "VALUES ('chan-1', 'general', 'text', 900, 'topic here', 22, 3, 0, "
      "NULL, 5, 10, NULL)");
  await run("INSERT INTO messages "
      "(id, channel_id, author_id, author_display_name, seq, content, "
      "created_at, edited_at, reply_to_id, pending, failed, failure_reason) "
      "VALUES ('m-1', 'chan-1', 'user-1', 'Mara', 1, 'already synced', "
      "1000, NULL, NULL, 0, 0, NULL)");
  await run('PRAGMA user_version = 11');
  await executor.executor.close();
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 11;

  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails details) async {}
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('slimm-migration-v12');
    file = File('${dir.path}/slimm.sqlite');
    await _seedSchemaV11(file);
  });

  tearDown(() => dir.delete(recursive: true));

  test('an upgrading client gains a real channels.categoryId column', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Raw sqlite schema, not drift's row mapping: a missing column reads as null with no error.
    final columns = await db.customSelect('PRAGMA table_info(channels)').get();
    expect(
      columns.map((r) => r.read<String>('name')),
      contains('category_id'),
      reason: 'new on both sides this release - nothing to backfill it from',
    );

    final channel = await db.select(db.channels).getSingle();
    expect(channel.categoryId, null);
  });

  test('an upgrading client gains an empty channel_categories table', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final categories = await db.select(db.channelCategories).get();

    expect(
      categories,
      isEmpty,
      reason: 'the next channel refresh populates it via replaceCategories; '
          'the migration itself only has to make the table exist',
    );
  });

  test('the existing channel row survives the upgrade intact', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();

    expect(channel.id, 'chan-1');
    expect(channel.name, 'general');
    expect(channel.topic, 'topic here');
    expect(channel.cursor, 22);
    expect(channel.lastReadSeq, 3);
    expect(channel.position, 5);
    expect(channel.opCursor, 10);
  });

  test('the existing message row survives the upgrade intact', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final message = await db.select(db.messages).getSingle();

    expect(message.id, 'm-1');
    expect(message.content, 'already synced');
    expect(message.authorDisplayName, 'Mara');
  });
}
