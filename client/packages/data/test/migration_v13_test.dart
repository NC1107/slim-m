// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests the schema-13 migration, which is what an upgrading client needs to
/// hold a forwarded message's origin.
///
/// Adds in place and loses nothing, the same shape v12 took: the seven
/// `messages.forwarded*` columns are new on both sides in the same release,
/// so no existing row could ever need backfilling into them. Every other
/// suite opens a fresh version-13 database directly, so without this an
/// upgrade whose body silently did nothing would leave `schemaVersion` at 13
/// with none of the columns created, and nothing would notice until a real
/// client's local database was already stuck that way.
///
/// Forwards that predate this were composed into message text and are
/// indistinguishable from ordinary content by design. They stay exactly as
/// they read today rather than being guessed at, which is what the surviving
/// pre-upgrade row here pins.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

/// The seven columns a forward occupies, all added by this migration.
const _forwardColumns = [
  'forwarded_message_id',
  'forwarded_channel_id',
  'forwarded_author_id',
  'forwarded_author_display_name',
  'forwarded_author_avatar_updated_at',
  'forwarded_created_at',
  'forwarded_content',
];

/// Builds the schema exactly as version 12 left it: every column through
/// v12, and no `forwarded_*` column at all.
Future<void> _seedSchemaV12(File file) async {
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
      "is_personal_space, dm_participant_id, position, op_cursor, "
      "parent_message_id, category_id) "
      "VALUES ('chan-1', 'general', 'text', 900, 'topic here', 22, 3, 0, "
      "NULL, 5, 10, NULL, NULL)");
  await run("INSERT INTO messages "
      "(id, channel_id, author_id, author_display_name, seq, content, "
      "created_at, edited_at, reply_to_id, pending, failed, failure_reason) "
      "VALUES ('m-1', 'chan-1', 'user-1', 'Mara', 1, "
      "'Forwarded from Alice\n> hello', 1000, NULL, NULL, 0, 0, NULL)");
  await run('PRAGMA user_version = 12');
  await executor.executor.close();
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 12;

  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails details) async {}
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('slimm-migration-v13');
    file = File('${dir.path}/slimm.sqlite');
    await _seedSchemaV12(file);
  });

  tearDown(() => dir.delete(recursive: true));

  test('an upgrading client gains every forwarded column', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Raw sqlite schema, not drift's row mapping: a missing column reads as null with no error.
    final columns = await db.customSelect('PRAGMA table_info(messages)').get();
    final names = columns.map((r) => r.read<String>('name')).toSet();

    for (final column in _forwardColumns) {
      expect(
        names,
        contains(column),
        reason: 'new on both sides this release - nothing to backfill it from',
      );
    }
  });

  test('a message that predates the upgrade reads as forwarding nothing',
      () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final message = await db.select(db.messages).getSingle();

    expect(message.forwardedMessageId, null);
    expect(message.forwardedContent, null);
  });

  test('an old text-composed forward keeps the text it always had', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final message = await db.select(db.messages).getSingle();

    expect(
      message.content,
      'Forwarded from Alice\n> hello',
      reason: 'unparseable by design; it is left as the plain text it is',
    );
    expect(message.id, 'm-1');
    expect(message.authorDisplayName, 'Mara');
  });

  test('the existing channel row survives the upgrade intact', () async {
    final db = SlimmDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final channel = await db.select(db.channels).getSingle();

    expect(channel.name, 'general');
    expect(channel.cursor, 22);
    expect(channel.opCursor, 10);
  });
}
