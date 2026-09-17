// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// "Mark as unread" in the local store.
///
/// The server keeps the read marker monotonic on purpose, so an unread mark
/// is recorded beside it rather than by rewinding it. This mirrors that, and
/// the cases worth holding are the ones where the two could contradict each
/// other: a mark must not move the marker, and reading must clear the mark.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/src/database.dart';
import 'package:slimm_data/src/message_store.dart';
import 'package:slimm_data/src/rail_channel.dart';

Future<MessageStore> _store() async {
  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return MessageStore(db);
}

Future<void> _addChannel(MessageStore store, {int lastReadSeq = 0}) async {
  await store.db.into(store.db.channels).insert(
        ChannelsCompanion.insert(
          id: 'c1',
          name: 'general',
          kind: 'text',
          createdAt: 0,
          lastReadSeq: Value(lastReadSeq),
          cursor: Value(lastReadSeq),
        ),
      );
}

Future<Channel> _channel(MessageStore store) =>
    (store.db.select(store.db.channels)..where((c) => c.id.equals('c1')))
        .getSingle();

void main() {
  test('marking unread does not move the read marker', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 7);

    await store.setReadMarker('c1', 7, manuallyUnread: true);

    final row = await _channel(store);
    expect(row.manuallyUnread, isTrue);
    expect(
      row.lastReadSeq,
      7,
      reason: 'the marker is monotonic; the mark lives beside it',
    );
  });

  test('reading the channel clears the mark', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 7);
    await store.setReadMarker('c1', 7, manuallyUnread: true);

    await store.setReadMarker('c1', 9, manuallyUnread: false);

    final row = await _channel(store);
    expect(row.manuallyUnread, isFalse);
    expect(row.lastReadSeq, 9);
  });

  test('a stale marker still cannot move backwards', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 9);

    await store.setReadMarker('c1', 3, manuallyUnread: true);

    final row = await _channel(store);
    expect(row.lastReadSeq, 9, reason: 'a lower seq is ignored, as before');
    expect(
      row.manuallyUnread,
      isTrue,
      reason: 'the mark is independent of the seq and still lands',
    );
  });

  test('an untouched flag is left alone when only the seq advances', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 1);
    await store.setReadMarker('c1', 1, manuallyUnread: true);

    // The plain two-argument call, as the sync path uses it.
    await store.setReadMarker('c1', 4);

    final row = await _channel(store);
    expect(row.lastReadSeq, 4);
    expect(
      row.manuallyUnread,
      isTrue,
      reason: 'a caller that says nothing about the flag must not clear it',
    );
  });

  test('the rail shows a marked channel as unread with nothing new', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 5);
    await store.setReadMarker('c1', 5, manuallyUnread: true);

    final rail = railChannelKey(await _channel(store));

    expect(
      rail.unread,
      isTrue,
      reason: 'cursor == lastReadSeq, so only the mark can light this',
    );
  });

  test('an unmarked, fully-read channel is not unread', () async {
    final store = await _store();
    await _addChannel(store, lastReadSeq: 5);

    expect(railChannelKey(await _channel(store)).unread, isFalse);
  });
}
