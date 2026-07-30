// SPDX-License-Identifier: Apache-2.0
/// The role and member picker sheets `_pickTarget` opens must actually show
/// rows once their provider resolves. Both were empty regardless of load
/// state: `_pickTarget` pre-captured `ref.read(rolesProvider).valueOrNull`
/// (or `membersProvider`) as a plain closure variable, which reads
/// `AsyncLoading` on a cold `autoDispose` provider and never rebuilds once
/// the fetch actually lands.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' hide Channel;
import 'package:slimm_api/api.dart' as api show Channel;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/channel_overwrites_screen.dart';
import 'package:slimm_data/data.dart' show MessageStore, SlimmDatabase;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _me = Me(
  id: 'user-1',
  username: 'admin',
  displayName: 'Admin',
  createdAt: 0,
  permissions: -1,
);

/// Mirrors `channel_management_test.dart`'s harness: a session, an
/// [apiProvider] backed by [handler], and an in-memory local store seeded
/// with one channel, since the target picker only appears once a channel is
/// chosen. Picking a channel reads the local store's real (native) sqlite
/// stream, which needs [WidgetTester.runAsync] to resolve inside a widget
/// test: the fake test clock never advances it otherwise.
Future<void> _pumpToTargetPicker(
  WidgetTester tester, {
  required http.Response Function(http.Request) handler,
}) async {
  final db = SlimmDatabase(NativeDatabase.memory());
  await MessageStore(db).upsertChannels(const [
    api.Channel(id: 'c1', name: 'general', kind: 'text', createdAt: 0),
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
          meProvider.overrideWith((ref) async => _me),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: MockClient((request) async => handler(request)),
            );
            ref.onDispose(api.close);
            return api;
          }),
          storeProvider.overrideWith((ref) async {
            ref.onDispose(db.close);
            return MessageStore(db);
          }),
        ],
      ),
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const ChannelOverwritesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.runAsync(() async {
    await tester.tap(find.text('Choose a channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
  });
}

void main() {
  testWidgets('the role picker sheet lists the roles once they load', (
    tester,
  ) async {
    await _pumpToTargetPicker(
      tester,
      handler: (request) => request.url.path == '/roles'
          ? http.Response(
              jsonEncode([
                {
                  'id': 'r1',
                  'name': 'Moderators',
                  'permissions': 0,
                  'is_everyone': false,
                  'created_at': 0,
                },
              ]),
              200,
            )
          : http.Response('{}', 200),
    );

    // The Role tab is the default; open its picker.
    await tester.tap(find.text('Choose a role'));
    await tester.pumpAndSettle();

    expect(
      find.text('Moderators'),
      findsOneWidget,
      reason:
          'the sheet must render the role once rolesProvider resolves, '
          'not stay empty forever',
    );
  });

  testWidgets('the member picker sheet lists the members once they load', (
    tester,
  ) async {
    await _pumpToTargetPicker(
      tester,
      handler: (request) => request.url.path == '/members'
          ? http.Response(
              jsonEncode([
                {
                  'id': 'u2',
                  'username': 'kit',
                  'display_name': 'Kit',
                  'created_at': 0,
                },
              ]),
              200,
            )
          : http.Response('{}', 200),
    );

    await tester.tap(find.text('Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a member'));
    await tester.pumpAndSettle();

    expect(
      find.text('Kit'),
      findsOneWidget,
      reason:
          'the sheet must render the member once membersProvider '
          'resolves, not stay empty forever',
    );
  });

  testWidgets(
    'clearing an overwrite reports the resulting state, not a claimed change',
    (tester) async {
      // Tall enough that the sixteen permission rows leave "Clear" on screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var deleted = false;
      await _pumpToTargetPicker(
        tester,
        handler: (request) {
          if (request.url.path == '/roles') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'r1',
                  'name': 'Moderators',
                  'permissions': 0,
                  'is_everyone': false,
                  'created_at': 0,
                },
              ]),
              200,
            );
          }
          if (request.method == 'DELETE' &&
              request.url.path == '/channels/c1/overwrites/role/r1') {
            deleted = true;
            return http.Response('', 204);
          }
          return http.Response('{}', 200);
        },
      );

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Clear').last);
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      expect(
        find.textContaining('cleared'),
        findsNothing,
        reason:
            'there is no read-back route, so the screen never knew whether '
            'an overwrite existed to clear in the first place',
      );
      expect(
        find.textContaining('now inherits every permission'),
        findsOneWidget,
      );
    },
  );
}
