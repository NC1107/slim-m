// SPDX-License-Identifier: Apache-2.0
/// Whether `watchChannel`'s stream ever emits a row set in which a message
/// just sent has no predecessor, even though older messages already exist in
/// the channel.
///
/// This is the direct question docs/BACKLOG.md's "sending a message flashes a
/// day divider" entry leaves open: the UI-level day divider comes from
/// `previous == null` for the row directly above the sent message
/// (`message_transcript.dart`'s `isNewDay`), and that can only be a genuine
/// data artifact if the stream itself reports it, not a rendering quirk.
/// Every emission is captured directly off the stream, with no widget layer
/// in between, so this isolates the store from the UI entirely.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

api.Message _message(String id, int seq, int createdAt) => api.Message(
      id: id,
      channelId: 'chan-1',
      authorId: 'alice',
      authorDisplayName: 'Alice',
      seq: seq,
      content: 'message $seq',
      createdAt: createdAt,
      editedAt: null,
    );

void main() {
  test(
    'the optimistic insert and the server-copy replacement never leave the '
    'sent message as the oldest row while real history exists',
    () async {
      final db = SlimmDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = MessageStore(db);
      await store.upsertChannels([
        const api.Channel(
          id: 'chan-1',
          name: 'general',
          kind: 'text',
          createdAt: 0,
        ),
      ]);

      final now = DateTime.now().millisecondsSinceEpoch;
      await store.applyMessages([
        _message('m1', 1, now - 5000),
        _message('m2', 2, now - 4000),
        _message('m3', 3, now - 3000),
      ]);

      final snapshots = <List<Message>>[];
      final sub = store.watchChannel('chan-1').listen(snapshots.add);
      addTearDown(sub.cancel);

      // Let the initial snapshot land before the write this test is about.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      snapshots.clear();

      await store.addPending(
        id: 'new',
        channelId: 'chan-1',
        authorId: 'bob',
        content: 'hello',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await store.applyMessage(_message('new', 4, now));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        snapshots,
        isNotEmpty,
        reason: 'the two writes above must have produced at least one '
            'emission each, or this test is not exercising anything',
      );

      for (final snapshot in snapshots) {
        final index = snapshot.indexWhere((m) => m.id == 'new');
        if (index == -1) continue;
        expect(
          index,
          greaterThan(0),
          reason: 'the sent message ("new") must never be the oldest row in a '
              'snapshot: $snapshot',
        );
      }
    },
  );
}
