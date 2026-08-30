// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// CD2: the local store had no retention at all - every delivered row ever
/// synced or paged in stayed for the life of the install. These pin the two
/// rules a sweep leans on: [MessageStore.pruneToRetentionCeiling] never
/// drops more than the oldest-past-the-ceiling delivered rows of any one
/// channel, and never touches a pending or failed send regardless of how
/// old it is; [MessageStore.reachableMessageIds] is a plain read of whatever
/// survived that for the channels asked about.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

api.Message _message(String channelId, int seq) => api.Message(
      id: '$channelId-m$seq',
      channelId: channelId,
      authorId: 'user-1',
      authorDisplayName: 'User One',
      seq: seq,
      content: 'message $seq',
      createdAt: seq * 1000,
      editedAt: null,
    );

Future<MessageStore> _store(List<String> channelIds) async {
  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final store = MessageStore(db);
  await store.upsertChannels([
    for (final id in channelIds)
      api.Channel(id: id, name: id, kind: 'text', createdAt: 0),
  ]);
  return store;
}

/// Every seq currently held for [channelId], including pending/failed rows
/// (`seq` 0), oldest first. Deliberately not capped: a real cap is exactly
/// what these tests are proving [pruneToRetentionCeiling] enforces.
Future<List<int>> _seqsOf(MessageStore store, String channelId) async {
  final rows = await store.watchChannel(channelId, limit: 10000).first;
  return rows.map((r) => r.seq).toList();
}

void main() {
  test('a channel past the ceiling keeps only its newest rows', () async {
    final store = await _store(['c1']);
    await store
        .applyMessages([for (var s = 1; s <= 10; s++) _message('c1', s)]);

    await store.pruneToRetentionCeiling(4);

    expect(await _seqsOf(store, 'c1'), [7, 8, 9, 10]);
  });

  test('a channel at or under the ceiling is left untouched', () async {
    final store = await _store(['c1']);
    await store.applyMessages([for (var s = 1; s <= 3; s++) _message('c1', s)]);

    await store.pruneToRetentionCeiling(5);

    expect(await _seqsOf(store, 'c1'), [1, 2, 3]);
  });

  test('a channel with exactly the ceiling many rows is left untouched',
      () async {
    final store = await _store(['c1']);
    await store.applyMessages([for (var s = 1; s <= 5; s++) _message('c1', s)]);

    await store.pruneToRetentionCeiling(5);

    expect(await _seqsOf(store, 'c1'), [1, 2, 3, 4, 5]);
  });

  test('a pending or failed send never gets pruned, no matter how old',
      () async {
    final store = await _store(['c1']);
    await store
        .applyMessages([for (var s = 1; s <= 10; s++) _message('c1', s)]);
    await store.addPending(
      id: 'queued',
      channelId: 'c1',
      authorId: 'user-1',
      content: 'not sent yet',
    );
    await store.addPending(
      id: 'doomed',
      channelId: 'c1',
      authorId: 'user-1',
      content: 'will fail',
    );
    await store.markFailed('doomed', reason: 'offline');

    await store.pruneToRetentionCeiling(4);

    final ids = (await store.watchChannel('c1', limit: 10000).first)
        .map((r) => r.id)
        .toSet();
    expect(ids.containsAll(['queued', 'doomed']), isTrue);
    // Newest 4 delivered, then the two pending/failed rows (`seq` 0) last.
    expect(await _seqsOf(store, 'c1'), [7, 8, 9, 10, 0, 0]);
  });

  test('each channel is capped independently of the others', () async {
    final store = await _store(['c1', 'c2']);
    await store
        .applyMessages([for (var s = 1; s <= 10; s++) _message('c1', s)]);
    await store.applyMessages([for (var s = 1; s <= 2; s++) _message('c2', s)]);

    await store.pruneToRetentionCeiling(3);

    expect(await _seqsOf(store, 'c1'), [8, 9, 10]);
    expect(await _seqsOf(store, 'c2'), [1, 2]);
  });

  test('reachableMessageIds reads whatever pruning already left', () async {
    final store = await _store(['c1', 'c2']);
    await store
        .applyMessages([for (var s = 1; s <= 10; s++) _message('c1', s)]);
    await store.applyMessages([for (var s = 1; s <= 2; s++) _message('c2', s)]);
    await store.pruneToRetentionCeiling(3);

    final reachable = await store.reachableMessageIds(['c1']);

    expect(reachable, {'c1-m8', 'c1-m9', 'c1-m10'});
  });

  test('reachableMessageIds ignores channels not asked about', () async {
    final store = await _store(['c1', 'c2']);
    await store.applyMessages([_message('c1', 1), _message('c2', 1)]);

    expect(await store.reachableMessageIds(['c1']), {'c1-m1'});
    expect(await store.reachableMessageIds([]), isEmpty);
  });
}
