// SPDX-License-Identifier: Apache-2.0
/// A DM with somebody already blocked used to open as a blank transcript
/// with a live composer that would only ever fail on send (the channel is
/// frozen server-side for that pair; see `store/dms.rs`). This drives the
/// real screen and asserts the composer is replaced by an explanation
/// instead, and that an ordinary DM is unaffected.
library;

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
import 'package:slimm_app/src/widgets/composer.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

http.Response _emptyJsonList() => http.Response(
  jsonEncode([]),
  200,
  headers: {'content-type': 'application/json'},
);

/// Pumps `ChannelScreen` for a DM already in the local store, its row
/// carrying [otherUserId] as the participant `channelFromDm` would have set,
/// and `GET /blocks` naming [blockedIds] as blocked.
Future<void> _pump(
  WidgetTester tester, {
  required String otherUserId,
  required Set<String> blockedIds,
}) async {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final store = MessageStore(db);
  await store.upsertChannels([
    api.Channel(
      id: 'dm-1',
      name: 'Alice',
      kind: 'dm',
      createdAt: 0,
      dmParticipantId: otherUserId,
    ),
  ]);

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      storeProvider.overrideWith((ref) async => store),
      syncControllerProvider.overrideWith((ref) => _NoopSyncController(ref)),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.method == 'GET' && request.url.path == '/me') {
              return http.Response(
                jsonEncode({
                  'id': 'bob',
                  'username': 'bob',
                  'display_name': 'Bob',
                  'created_at': 0,
                  'permissions': 0,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.method == 'GET' && request.url.path == '/blocks') {
              return http.Response(
                jsonEncode(blockedIds.toList()),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return _emptyJsonList();
          }),
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
        home: const Scaffold(body: ChannelScreen(channelId: 'dm-1')),
      ),
    ),
  );

  // Bounded, not pumpAndSettle: see channel_screen_test.dart's own note on AppIconButton's ripple.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Unmounts before the framework's own teardown runs its pending-timers
/// check: `ChannelScreen`'s `StreamBuilder`s defer their drift cleanup onto
/// a zero-duration `Timer`, and that check runs before that timer's turn
/// otherwise, failing on something this file is not testing at all.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  testWidgets(
    'a DM with a blocked participant shows why instead of a live composer',
    (tester) async {
      await _pump(tester, otherUserId: 'alice', blockedIds: {'alice'});

      expect(
        find.byType(Composer),
        findsNothing,
        reason:
            'the server refuses send/react/attach both ways for a blocked '
            'DM, so a live composer here can only ever fail',
      );
      expect(find.textContaining('You have blocked Alice'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets('an ordinary DM keeps its live composer', (tester) async {
    await _pump(tester, otherUserId: 'alice', blockedIds: const {});

    expect(find.byType(Composer), findsOneWidget);
    expect(find.textContaining('You have blocked'), findsNothing);
    await _unmount(tester);
  });
}
