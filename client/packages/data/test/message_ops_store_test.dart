// SPDX-License-Identifier: Apache-2.0
/// Tests for the op cursor and the edit application, the local half of
/// reconciling an edit or a delete that happened while this client was away.
///
/// The rules here are conventions with no type behind them - never insert,
/// never write `seq`, never advance the message cursor, clear to null rather
/// than lower to zero - and each is a one-word mistake with no symptom until
/// much later. These are what stand in for a compiler.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

api.Message _message({
  required String id,
  int seq = 1,
  String content = 'hello',
  int? editedAt,
}) =>
    api.Message(
      id: id,
      channelId: 'chan-1',
      authorId: 'user-1',
      authorDisplayName: 'User One',
      seq: seq,
      content: content,
      createdAt: 1000,
      editedAt: editedAt,
    );

/// The cursor lives on the channel row itself; there is no dedicated reader.
Future<int> _cursorOf(MessageStore store, String channelId) async {
  final channels = await store.allChannels();
  return channels.firstWhere((c) => c.id == channelId).cursor;
}

void main() {
  late SlimmDatabase db;
  late MessageStore store;

  setUp(() async {
    db = SlimmDatabase(NativeDatabase.memory());
    store = MessageStore(db);
    await store.upsertChannels([
      const api.Channel(
          id: 'chan-1', name: 'general', kind: 'text', createdAt: 1),
    ]);
  });

  tearDown(() => db.close());

  test('an edit replaces the content in place', () async {
    await store.applyMessage(_message(id: 'm1', seq: 4));

    await store.applyEdit('m1', 'revised', 2000);

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.single.content, 'revised');
    expect(rows.single.editedAt, 2000);
  });

  test('an edit leaves the message seq and the channel cursor alone', () async {
    // Advancing the message cursor would skip whatever sits before the edit.
    await store.applyMessage(_message(id: 'm1', seq: 4));

    await store.applyEdit('m1', 'revised', 2000);

    final rows = await store.watchChannel('chan-1').first;
    expect(rows.single.seq, 4);
    expect(await _cursorOf(store, 'chan-1'), 4);
  });

  test('an edit for a message this client never held inserts nothing',
      () async {
    // The alternative is a row with no seq, sorting in as a phantom.
    await store.applyEdit('never-seen', 'revised', 2000);

    final rows = await store.watchChannel('chan-1').first;
    expect(rows, isEmpty);
  });

  test('the op cursor starts null, which is not zero', () async {
    expect(await store.opCursorFor('chan-1'), null);
  });

  test('the op cursor moves forward and never backwards', () async {
    await store.setOpCursor('chan-1', 5);
    expect(await store.opCursorFor('chan-1'), 5);

    await store.setOpCursor('chan-1', 3);
    expect(await store.opCursorFor('chan-1'), 5,
        reason: 'the cursor is a high-water mark');

    await store.setOpCursor('chan-1', 9);
    expect(await store.opCursorFor('chan-1'), 9);
  });

  test('null clears the op cursor rather than lowering it to zero', () async {
    await store.setOpCursor('chan-1', 5);

    await store.setOpCursor('chan-1', null);

    expect(await store.opCursorFor('chan-1'), null,
        reason:
            'zero would claim to be caught up from the start of the stream');
  });

  test('a reset clears the op cursor as well as the message one', () async {
    // Otherwise a server that has swept past it can only answer reset again.
    await store.applyMessage(_message(id: 'm1', seq: 4));
    await store.setOpCursor('chan-1', 5);

    await store.resetChannel('chan-1');

    expect(await _cursorOf(store, 'chan-1'), 0);
    expect(await store.opCursorFor('chan-1'), null);
  });

  test('a catch-up request carries both cursors', () async {
    await store.applyMessage(_message(id: 'm1', seq: 4));
    await store.setOpCursor('chan-1', 5);

    final cursors = await store.allCursors();

    expect(cursors, hasLength(1));
    expect(cursors.single.afterSeq, 4);
    expect(cursors.single.afterOpSeq, 5);
  });

  test('a channel with no op cursor asks for no ops', () async {
    // Absent opts the scope out, so a new and an old client take one branch.
    final cursors = await store.allCursors();

    expect(cursors.single.afterOpSeq, null);
    expect(cursors.single.toJson().containsKey('after_op_seq'), false);
  });
}
