// SPDX-License-Identifier: Apache-2.0
/// Tests for the local store's two invariants: writes are idempotent by message
/// id, and a stale copy can never overwrite a newer one. Both delivery routes
/// (live push and catch-up) rely on those holding under any interleaving.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

api.Message _message({
  required String id,
  String channelId = 'chan-1',
  String? authorId = 'user-1',
  int seq = 1,
  String content = 'hello',
  int createdAt = 1000,
  int? editedAt,
}) =>
    api.Message(
      id: id,
      channelId: channelId,
      authorId: authorId,
      seq: seq,
      content: content,
      createdAt: createdAt,
      editedAt: editedAt,
    );

void main() {
  late SlimmDatabase db;
  late MessageStore store;

  setUp(() async {
    db = SlimmDatabase(NativeDatabase.memory());
    store = MessageStore(db);
    await store.upsertChannels([
      const api.Channel(
          id: 'chan-1', name: 'general', kind: 'text', createdAt: 1),
      const api.Channel(
          id: 'chan-2', name: 'other', kind: 'text', createdAt: 2),
    ]);
  });

  tearDown(() => db.close());

  test('applying the same message twice stores it once', () async {
    final message = _message(id: 'm1', seq: 1);
    await store.applyMessage(message);
    // The same message can genuinely arrive twice: once live over the socket,
    // once from a catch-up covering the same range.
    await store.applyMessage(message);

    final rows = await store.watchChannel('chan-1').first;
    expect(rows, hasLength(1));
    expect(rows.single.id, 'm1');
  });

  test('a stale copy never overwrites a newer one', () async {
    await store.applyMessage(
      _message(id: 'm1', seq: 5, content: 'edited', editedAt: 2000),
    );
    // A late catch-up delivering the pre-edit version must not undo the edit.
    await store.applyMessage(_message(id: 'm1', seq: 3, content: 'original'));

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.single.content, 'edited');
    expect(rows.single.seq, 5);
  });

  test('an edit at a higher seq does replace the stored copy', () async {
    await store.applyMessage(_message(id: 'm1', seq: 3, content: 'original'));
    await store.applyMessage(
      _message(id: 'm1', seq: 3, content: 'edited', editedAt: 2000),
    );

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.single.content, 'edited');
    expect(rows.single.editedAt, 2000);
  });

  test('the cursor only ever moves forward', () async {
    await store.applyMessage(_message(id: 'm1', seq: 1));
    await store.applyMessage(_message(id: 'm3', seq: 3));
    expect(await store.cursorFor('chan-1'), 3);

    // Backfilling an older message must not rewind the resume point.
    await store.applyMessage(_message(id: 'm2', seq: 2));
    expect(await store.cursorFor('chan-1'), 3);
  });

  test('cursors are per channel', () async {
    await store.applyMessage(_message(id: 'a', channelId: 'chan-1', seq: 7));
    await store.applyMessage(_message(id: 'b', channelId: 'chan-2', seq: 2));

    expect(await store.cursorFor('chan-1'), 7);
    expect(await store.cursorFor('chan-2'), 2);

    final cursors = await store.allCursors();
    expect(cursors.map((c) => '${c.channelId}:${c.afterSeq}').toSet(),
        {'chan-1:7', 'chan-2:2'});
  });

  test('the server copy replaces the optimistic echo in place', () async {
    await store.addPending(
      id: 'local-1',
      channelId: 'chan-1',
      authorId: 'user-1',
      content: 'typed by the user',
    );
    var rows = await store.watchChannel('chan-1').first;
    expect(rows.single.pending, isTrue);
    expect(rows.single.seq, 0, reason: 'no server order yet');

    // The acknowledgement carries the same client-generated id, so it lands on
    // the same row rather than appearing as a duplicate.
    await store.applyMessage(
      _message(id: 'local-1', seq: 4, content: 'typed by the user'),
    );

    rows = await store.watchChannel('chan-1').first;
    expect(rows, hasLength(1), reason: 'no duplicate beside the echo');
    expect(rows.single.pending, isFalse);
    expect(rows.single.seq, 4);
  });

  test('a failed send is kept so the user does not lose it', () async {
    await store.addPending(
      id: 'local-1',
      channelId: 'chan-1',
      authorId: 'user-1',
      content: 'important',
    );
    await store.markFailed('local-1');

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.single.failed, isTrue);
    expect(rows.single.pending, isFalse);
    expect(rows.single.content, 'important');

    await store.discard('local-1');
    expect(await store.watchChannel('chan-1').first, isEmpty);
  });

  test('unread is derived from the read marker', () async {
    await store.applyMessages([
      _message(id: 'm1', seq: 1),
      _message(id: 'm2', seq: 2),
      _message(id: 'm3', seq: 3),
    ]);
    expect(await store.unreadCount('chan-1'), 3);

    await store.setReadMarker('chan-1', 2);
    expect(await store.unreadCount('chan-1'), 1);

    // The marker is monotonic, so a stale read receipt cannot resurrect unreads.
    await store.setReadMarker('chan-1', 1);
    expect(await store.unreadCount('chan-1'), 1);
  });

  test('a pending send is not counted as unread', () async {
    await store.addPending(
      id: 'local-1',
      channelId: 'chan-1',
      authorId: 'user-1',
      content: 'mine',
    );
    // The user's own unsent message is not something they have yet to read.
    expect(await store.unreadCount('chan-1'), 0);
  });

  test('reset clears the channel but keeps unsent work', () async {
    await store.applyMessages([
      _message(id: 'm1', seq: 1),
      _message(id: 'm2', seq: 2),
    ]);
    await store.addPending(
      id: 'local-1',
      channelId: 'chan-1',
      authorId: 'user-1',
      content: 'still typing',
    );

    await store.resetChannel('chan-1');

    final rows = await store.watchChannel('chan-1').first;
    expect(rows, hasLength(1));
    expect(rows.single.id, 'local-1', reason: 'the unsent message survives');
    expect(await store.cursorFor('chan-1'), 0,
        reason: 'refetch from the start');
  });

  test('out-of-order arrival still reads back in seq order', () async {
    await store.applyMessage(_message(id: 'm3', seq: 3, content: 'third'));
    await store.applyMessage(_message(id: 'm1', seq: 1, content: 'first'));
    await store.applyMessage(_message(id: 'm2', seq: 2, content: 'second'));

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.map((m) => m.content), ['first', 'second', 'third']);
  });

  test('a channel refresh keeps the local cursor and read marker', () async {
    await store.applyMessage(_message(id: 'm1', seq: 9));
    await store.setReadMarker('chan-1', 5);

    // Re-fetching the channel list must not wipe local sync state.
    await store.upsertChannels([
      const api.Channel(
          id: 'chan-1', name: 'general-renamed', kind: 'text', createdAt: 1),
    ]);

    expect(await store.cursorFor('chan-1'), 9);
    final channels = await store.watchChannels().first;
    final channel = channels.firstWhere((c) => c.id == 'chan-1');
    expect(channel.name, 'general-renamed');
    expect(channel.lastReadSeq, 5);
  });
}
