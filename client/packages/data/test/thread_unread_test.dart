// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A thread never puts an unread badge on the channel rail.
///
/// Asked directly from real device use: "not sure if threads are invoking as
/// unread and making a badge in the channel view." The answer is no, and this
/// pins it, because the reasons are two separate mechanisms and either one
/// changing would be easy to miss.
///
/// The rail renders `channel.cursor > channel.lastReadSeq` per row
/// (`channel_rail_sections.dart`), and that is the only place in the client
/// that predicate appears. So the whole question is which rows the rail is
/// handed, which is `MessageStore.watchChannels()` - and it filters
/// `parentMessageId.isNull()`, so a thread's own row is never among them
/// however unread it is.
///
/// Separately, a reply into a thread carries the *thread's* channel id, so it
/// advances that channel's cursor and never the parent's. Both halves are
/// asserted here: a thread reply must neither surface a row of its own nor
/// light the parent it hangs off.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

api.Channel _channel(String id, {String? parentMessageId}) => api.Channel(
      id: id,
      name: parentMessageId == null ? id : '',
      kind: 'text',
      createdAt: 0,
      parentMessageId: parentMessageId,
    );

api.Message _message(String id, String channelId, int seq) => api.Message(
      id: id,
      channelId: channelId,
      authorId: 'someone-else',
      authorDisplayName: 'Someone Else',
      seq: seq,
      content: 'a reply',
      createdAt: 1000,
      editedAt: null,
    );

/// The rail's own predicate, applied to whatever rows it is handed.
bool _wouldBadge(Channel row) => row.cursor > row.lastReadSeq;

void main() {
  late SlimmDatabase db;
  late MessageStore store;

  setUp(() {
    db = SlimmDatabase(NativeDatabase.memory());
    store = MessageStore(db);
  });

  tearDown(() async => db.close());

  test('a thread with unread replies never reaches the rail', () async {
    await store.upsertChannels([
      _channel('general'),
      _channel('thread-1', parentMessageId: 'msg-in-general'),
    ]);
    await store.applyMessages([_message('m1', 'thread-1', 1)]);

    final rows = await store.watchChannels().first;
    expect(
      rows.map((c) => c.id),
      isNot(contains('thread-1')),
      reason: 'a thread must never be a rail row, so it can never badge one',
    );
  });

  test('a thread reply does not advance the parent channel', () async {
    await store.upsertChannels([
      _channel('general'),
      _channel('thread-1', parentMessageId: 'msg-in-general'),
    ]);
    await store.applyMessages([_message('m1', 'thread-1', 1)]);

    final all = await store.allChannels();
    final parent = all.firstWhere((c) => c.id == 'general');
    expect(
      _wouldBadge(parent),
      isFalse,
      reason: 'a reply carries the thread\'s own channel id, so the parent '
          'it hangs off must be untouched',
    );
  });

  test('an ordinary channel with unread still badges', () async {
    await store.upsertChannels([_channel('general')]);
    await store.applyMessages([_message('m1', 'general', 1)]);

    final rows = await store.watchChannels().first;
    final general = rows.firstWhere((c) => c.id == 'general');
    expect(
      _wouldBadge(general),
      isTrue,
      reason: 'the control: without this the other two would pass with '
          'unread reporting broken outright',
    );
  });
}
