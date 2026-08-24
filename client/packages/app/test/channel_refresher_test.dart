// SPDX-License-Identifier: Apache-2.0
/// `ChannelRefresher` refreshes the channel and DM listings, hydrates each
/// channel's read marker, and dedups a concurrent refresh into the one already
/// running. None of that was tested: `sync_controller_race_test` drives the
/// whole `SyncController` and only trips the outer `isCurrent` checkpoint for
/// one sign-out race, never the dedup, the discard, the per-channel error
/// isolation, or the second checkpoint inside the read-marker loop.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/channel_refresher.dart';
import 'package:slimm_data/data.dart' show MessageStore, SlimmDatabase;

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'a',
  refreshToken: 'r',
  accessExpiresAt: 9999999999999,
);

const _twoChannels = [
  {'id': 'chan-1', 'name': 'general', 'kind': 'text', 'created_at': 1},
  {'id': 'chan-2', 'name': 'random', 'kind': 'text', 'created_at': 2},
];

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// A refresher fixture: the store to inspect afterwards, the api to drive, and
/// a per-path request tally so a dedup can be proven as one round trip.
class _Fixture {
  _Fixture(this.db, this.store, this.api, this.hits);
  final SlimmDatabase db;
  final MessageStore store;
  final SlimmApi api;
  final Map<String, int> hits;
}

/// Builds an api whose `/channels` returns [channels], whose `/read` for any
/// id in [failingReads] answers 500, and otherwise reports [readSeq]. Every
/// request is tallied by path.
_Fixture _fixture({
  List<Map<String, Object>> channels = _twoChannels,
  Set<String> failingReads = const {},
  int readSeq = 5,
}) {
  final db = SlimmDatabase(NativeDatabase.memory());
  final store = MessageStore(db);
  final hits = <String, int>{};
  final api = SlimmApi(
    baseUrl: Uri.parse('http://localhost:8080'),
    session: SessionStore(tokens: _tokens),
    httpClient: MockClient((request) async {
      final path = request.url.path;
      hits[path] = (hits[path] ?? 0) + 1;
      if (path == '/channels') return _json(channels);
      if (path == '/categories') return _json(<Object>[]);
      if (path == '/dms') return _json(<Object>[]);
      if (path.endsWith('/read')) {
        final id = path.split('/')[2];
        if (failingReads.contains(id)) {
          return http.Response(
            '{"error":"nope"}',
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return _json({'last_read_seq': readSeq, 'unread': 0});
      }
      return http.Response('not found', 404);
    }),
  );
  return _Fixture(db, store, api, hits);
}

Future<int?> _marker(MessageStore store, String id) async {
  final channels = await store.allChannels();
  return channels
      .where((c) => c.id == id)
      .map((c) => c.lastReadSeq)
      .firstOrNull;
}

void main() {
  test('two concurrent refreshes collapse into one round trip', () async {
    final f = _fixture();
    addTearDown(f.db.close);
    final refresher = ChannelRefresher();

    final a = refresher.refreshOnce(f.api, f.store, isCurrent: () => true);
    final b = refresher.refreshOnce(f.api, f.store, isCurrent: () => true);
    await Future.wait([a, b]);

    expect(identical(a, b), isTrue, reason: 'the second joins the first');
    expect(
      f.hits['/channels'],
      1,
      reason: 'not one listing fetched per caller',
    );
  });

  test('discardInFlight lets the next caller start a fresh refresh', () async {
    final f = _fixture();
    addTearDown(f.db.close);
    final refresher = ChannelRefresher();

    final a = refresher.refreshOnce(f.api, f.store, isCurrent: () => true);
    // A new session: the later caller must not inherit the old guard's future.
    refresher.discardInFlight();
    final b = refresher.refreshOnce(f.api, f.store, isCurrent: () => true);
    await Future.wait([a, b]);

    expect(identical(a, b), isFalse);
    expect(f.hits['/channels'], 2, reason: 'each session refreshed for itself');
  });

  test('one channel failing its read state does not stop the others', () async {
    final f = _fixture(failingReads: {'chan-1'}, readSeq: 7);
    addTearDown(f.db.close);

    await ChannelRefresher().refresh(f.api, f.store, isCurrent: () => true);

    expect(
      await _marker(f.store, 'chan-2'),
      7,
      reason: 'its marker still lands',
    );
    expect(
      await _marker(f.store, 'chan-1'),
      0,
      reason: 'the failed read is best-effort, left for the next refresh',
    );
  });

  test(
    'isCurrent false on entry writes nothing the sign-out cleared',
    () async {
      final f = _fixture();
      addTearDown(f.db.close);

      await ChannelRefresher().refresh(f.api, f.store, isCurrent: () => false);

      expect(
        await f.store.allChannels(),
        isEmpty,
        reason: 'no channels written',
      );
      expect(
        f.hits.keys.any((p) => p.endsWith('/read')),
        isFalse,
        reason: 'it returns before the read-marker loop, so no read is fetched',
      );
    },
  );

  test(
    'isCurrent flipping false mid-loop stops the read-marker writes',
    () async {
      final f = _fixture(readSeq: 9);
      addTearDown(f.db.close);

      // True for the entry check, false for every per-channel check after it.
      var checks = 0;
      await ChannelRefresher().refresh(
        f.api,
        f.store,
        isCurrent: () => (checks++) == 0,
      );

      expect(
        (await f.store.allChannels()).map((c) => c.id),
        containsAll(['chan-1', 'chan-2']),
        reason: 'the entry check passed, so the listing was written',
      );
      expect(await _marker(f.store, 'chan-1'), 0);
      expect(await _marker(f.store, 'chan-2'), 0);
    },
  );
}
