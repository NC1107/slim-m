// SPDX-License-Identifier: Apache-2.0
/// A real [ChannelScreen] over a real local store and a fake server that
/// answers `GET /channels/{id}/messages` the way the real one does: newest
/// first, keyset-paginated on `seq`, capped by `limit`.
///
/// Paging backwards and knowing where a channel starts are both answers the
/// client can only get from that endpoint's shape, so a fake that returned a
/// fixed list would prove nothing about either.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/channel_screen.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// Stands in for the real [SyncController]; see `channel_screen_test.dart`,
/// which needs the same seam for the same reason.
///
/// Reports [_status] from `start` rather than leaving it at the base
/// constructor's initial `offline`: the empty-transcript synthesis in
/// `channel_screen.dart` only fires at [SyncStatus.live], and nothing else in
/// this harness can ever move it there.
class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref, this._status);

  final SyncStatus _status;

  @override
  Future<void> start() async {
    state = _status;
  }
}

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

api.Message channelMessage(int seq, {String authorId = 'alice'}) => api.Message(
  id: 'm$seq',
  channelId: 'c1',
  authorId: authorId,
  authorDisplayName: authorId,
  seq: seq,
  content: 'message $seq',
  createdAt: seq * 60000,
  editedAt: null,
);

Map<String, dynamic> _meJson() => {
  'id': 'bob',
  'username': 'bob',
  'display_name': 'Bob',
  'created_at': 0,
  'permissions': 0,
};

/// A bounded pump count rather than `pumpAndSettle`, which never returns
/// here: `AppButton`'s hover and focus machinery keeps a frame scheduled.
Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The transcript's own [ScrollController], the same instance `ChannelScreen`
/// drives internally, so moving it here is what a real drag would do.
ScrollController transcriptScroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

/// How many rows the transcript was handed, the top slot included. The list
/// builds lazily, so this is the only viewport-independent measure of how
/// much history actually reached it.
int transcriptItemCount(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView));
  return (list.childrenDelegate as SliverChildBuilderDelegate).childCount!;
}

/// Puts the reader at the oldest end. The list is reversed, so that is the
/// maximum extent, not the minimum.
///
/// Repeated because a lazy [ListView] only estimates its maximum extent from
/// the slivers it has built, so one jump lands short of the real end and the
/// row the tests care about is never laid out.
Future<void> scrollToOldest(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    final position = transcriptScroll(tester).position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(position.maxScrollExtent);
    await flush(tester);
  }
}

class HistoryHarness {
  HistoryHarness({
    required this.db,
    required this.store,
    required this.container,
    required this.historyRequests,
    required Completer<void>? gate,
  }) : _gate = gate;

  final SlimmDatabase db;
  final MessageStore store;
  final ProviderContainer container;

  /// Every `GET .../messages` this screen made, in order, so a test can say
  /// what was asked for as well as what came back.
  final List<Uri> historyRequests;

  final Completer<void>? _gate;

  /// Lets a held backwards page answer. Until this is called the reader stays
  /// at the top of the list with the page still in flight, which is the only
  /// moment a test can look at what stands above the oldest loaded row.
  void releaseOlderPages() => _gate?.complete();

  /// The `before` cursor of every backwards page actually requested, in
  /// order, ignoring the plain `listMessages(limit: 50)` hydration fetch that
  /// carries none. What a test cares about when counting pages is this, not
  /// [historyRequests] itself, which also carries that one non-paging call.
  List<String?> get beforeCursors => historyRequests
      .where((u) => u.queryParameters.containsKey('before'))
      .map((u) => u.queryParameters['before'])
      .toList();
}

/// Mounts the screen with [serverSeqs] existing server-side and only
/// [seededSeqs] already in the local store, which is the state a client is in
/// after `/sync` or the screen's own 50-message hydration.
///
/// With [holdOlderPages] set, any request carrying a `before` cursor waits for
/// [HistoryHarness.releaseOlderPages]; a page that lands immediately grows the
/// list out from under the reader, which moves the top back off screen before
/// anything can be asserted about it. With [olderPagesFail] set, those same
/// requests are refused.
///
/// [messageAuthorId] names who every message in the channel is from, seeded
/// and server-side alike; [blockedUserIds] is who this viewer has blocked, so
/// a test can put the two together and mount a channel that is entirely
/// filtered from view. [syncStatus] is what [SyncController] reports once
/// `start` runs, since nothing else in this harness can move it off `offline`.
/// [storeFactory] swaps in a [MessageStore] subclass, for a test that needs
/// the store itself to misbehave rather than the network.
Future<HistoryHarness> mountChannel(
  WidgetTester tester, {
  required List<int> serverSeqs,
  required List<int> seededSeqs,
  bool holdOlderPages = false,
  bool olderPagesFail = false,
  String messageAuthorId = 'alice',
  List<String> blockedUserIds = const [],
  SyncStatus syncStatus = SyncStatus.offline,
  MessageStore Function(SlimmDatabase db)? storeFactory,
}) async {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final store = (storeFactory ?? MessageStore.new)(db);
  await store.upsertChannels([
    const api.Channel(id: 'c1', name: 'general', kind: 'text', createdAt: 0),
  ]);
  await store.applyMessages(
    seededSeqs.map((seq) => channelMessage(seq, authorId: messageAuthorId)),
  );

  final requests = <Uri>[];
  final gate = holdOlderPages ? Completer<void>() : null;
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      storeProvider.overrideWith((ref) async => store),
      syncControllerProvider.overrideWith(
        (ref) => _NoopSyncController(ref, syncStatus),
      ),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient(
            (request) => _answer(
              request,
              serverSeqs,
              requests,
              gate,
              olderPagesFail,
              messageAuthorId,
              blockedUserIds,
            ),
          ),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: ChannelScreen(channelId: 'c1')),
      ),
    ),
  );
  await flush(tester);

  return HistoryHarness(
    db: db,
    store: store,
    container: container,
    historyRequests: requests,
    gate: gate,
  );
}

Future<http.Response> _answer(
  http.Request request,
  List<int> serverSeqs,
  List<Uri> requests,
  Completer<void>? gate,
  bool olderPagesFail,
  String messageAuthorId,
  List<String> blockedUserIds,
) async {
  final path = request.url.path;
  if (request.method == 'GET' && path == '/channels/c1/messages') {
    requests.add(request.url);
    final older = request.url.queryParameters.containsKey('before');
    if (gate != null && older) await gate.future;
    if (olderPagesFail && older) {
      return http.Response(
        jsonEncode({'error': 'nope'}),
        500,
        headers: {'content-type': 'application/json'},
      );
    }
    return _jsonBody(_page(request.url, serverSeqs, messageAuthorId));
  }
  if (request.method == 'GET' && path == '/me') return _jsonBody(_meJson());
  if (request.method == 'GET' && path == '/blocks') {
    return _jsonBody(blockedUserIds);
  }
  if (request.method == 'PUT' && path == '/channels/c1/read') {
    return _jsonBody({'last_read_seq': 0, 'unread': 0});
  }
  // Members, pins and the rest answer empty; none of them are what these tests are about.
  return _jsonBody(const <Object>[]);
}

/// The server's own contract: live messages with `seq` below `before`,
/// newest first, at most `limit` of them.
List<Map<String, dynamic>> _page(
  Uri url,
  List<int> serverSeqs,
  String authorId,
) {
  final before = int.tryParse(url.queryParameters['before'] ?? '');
  final limit = int.tryParse(url.queryParameters['limit'] ?? '') ?? 50;
  final seqs = serverSeqs.where((s) => before == null || s < before).toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    for (final seq in seqs.take(limit))
      _messageJson(channelMessage(seq, authorId: authorId)),
  ];
}

Map<String, dynamic> _messageJson(api.Message message) => {
  'id': message.id,
  'channel_id': message.channelId,
  'author_id': message.authorId,
  'author_display_name': message.authorDisplayName,
  'seq': message.seq,
  'content': message.content,
  'created_at': message.createdAt,
};

http.Response _jsonBody(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
