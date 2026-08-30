// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// CA2: the channel-rail widget's optimistic-reorder overlay used drift's
/// `Value` directly; the wrap now lives behind `Channel.repositioned` in the
/// data layer. These pin that pure transform.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

void main() {
  late SlimmDatabase db;
  late MessageStore store;

  setUp(() async {
    db = SlimmDatabase(NativeDatabase.memory());
    store = MessageStore(db);
    await store.upsertChannels([
      const api.Channel(id: 'c1', name: 'general', kind: 'text', createdAt: 0),
    ]);
  });

  tearDown(() => db.close());

  test('repositioned sets position and category, leaving other fields',
      () async {
    final channel = (await store.channelRow('c1'))!;
    final moved = channel.repositioned(categoryId: 'cat-1', position: 3);

    expect(moved.position, 3);
    expect(moved.categoryId, 'cat-1');
    expect(moved.id, channel.id);
    expect(moved.name, channel.name);
    expect(moved.kind, channel.kind);
  });

  test('a null category places the channel at the top level', () async {
    final channel = (await store.channelRow('c1'))!;
    final top = channel.repositioned(categoryId: null, position: 0);

    expect(top.categoryId, isNull);
    expect(top.position, 0);
  });
}
