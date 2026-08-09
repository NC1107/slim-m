// SPDX-License-Identifier: Apache-2.0
/// The owner's report: a two-person DM's header offered a members toggle
/// that opened the deployment's whole roster, not the DM's two participants
/// - `membersProvider` is deliberately deployment-wide (see `member_pane.dart`'s
/// own doc comment), so nothing filtered it for a DM. The composer's hint
/// also named the other person with the channel-hash convention ("Message
/// #Alice"), and the canvas button offered a route that always 403s there
/// (`store/dms.rs`'s `DM_BASE` never grants `USE_CANVAS`). All three are
/// wired off `channel?.kind`, so this drives a real `ChannelScreen` for a DM
/// channel rather than asserting on `ChannelHeader` in isolation.
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

Map<String, dynamic> _meJson() => {
  'id': 'bob',
  'username': 'bob',
  'display_name': 'Bob',
  'created_at': 0,
  'permissions': 0,
};

http.Response _emptyJsonList() => http.Response(
  jsonEncode([]),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets('a DM header offers no members toggle, no canvas button, and the '
      'composer hint names nobody', (tester) async {
    // Expanded, so ChannelHeader (the wide header, absent below compact) builds.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = SlimmDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = MessageStore(db);
    await store.upsertChannels([
      const api.Channel(
        id: 'c1',
        name: 'Alice',
        kind: 'dm',
        createdAt: 0,
        dmParticipantId: 'alice',
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
                  jsonEncode(_meJson()),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              // Members, pins, and the extras-hydration fetch: none of
              // them are what this test is about, so all answer empty.
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
          home: const Scaffold(body: ChannelScreen(channelId: 'c1')),
        ),
      ),
    );

    // Not pumpAndSettle: AppIconButton's ripple/hover machinery keeps
    // requesting a frame in this environment, the same reason
    // channel_screen_test.dart uses a bounded pump count.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.bySemanticsLabel('Toggle member list'),
      findsNothing,
      reason:
          'a DM has two participants, never the deployment roster the '
          'toggle would open',
    );
    expect(
      find.bySemanticsLabel('Open canvas'),
      findsNothing,
      reason:
          "a DM's base permissions never grant USE_CANVAS, so this "
          'would 403 every time it was pressed',
    );

    final hint = tester.widget<Text>(find.byKey(const Key('composer-hint')));
    expect(
      hint.textSpan!.toPlainText(),
      'Message',
      reason:
          'a DM is not a "#channel", so its partner\'s name must not be '
          'rendered with the channel-hash convention',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
