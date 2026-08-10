// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the suites that drive [ChannelOverwritesScreen]: a
/// session, an [apiProvider] backed by a caller-supplied handler, and an
/// in-memory local store seeded with one channel, plus the tap sequence that
/// picks it. Not a `_test.dart` file, so `flutter test` does not try to run
/// it on its own.
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

const channelOverwritesTokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

// A field access on a const instance is not itself a Dart constant expression.
const channelOverwritesMePermissions = -1;

const channelOverwritesMe = Me(
  id: 'user-1',
  username: 'admin',
  displayName: 'Admin',
  createdAt: 0,
  permissions: channelOverwritesMePermissions,
);

/// [WidgetTester.pumpAndSettle] pumps frames, not real time, so it cannot be
/// trusted to wait out the real (non-fake-clock) sqlite read a channel pick
/// triggers: how many real microtask turns happen inside one `pump()` is a
/// race, and routing the row's tap through `AppListRow`'s own handler (one
/// more closure than a bare `ListTile.onTap`) reliably loses it here, where
/// it happened to reliably win before. This polls with real delays between
/// pumps until the target actually appears, rather than trusting one settle.
Future<void> settleUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

/// Mirrors `channel_management_test.dart`'s harness: a session, an
/// [apiProvider] backed by [handler], and an in-memory local store seeded
/// with one channel, since the target picker only appears once a channel is
/// chosen. Picking a channel reads the local store's real (native) sqlite
/// stream, which needs [WidgetTester.runAsync] to resolve inside a widget
/// test: the fake test clock never advances it otherwise.
///
/// [channelPermissions] answers `GET /channels/c1/permissions` - the "Allow"
/// gate's real source since docs/decisions/0011-per-channel-permissions.md -
/// defaulting to [channelOverwritesMe]'s own base set so a test naming
/// neither still reads as "this caller can do anything".
Future<void> pumpToTargetPicker(
  WidgetTester tester, {
  required http.Response Function(http.Request) handler,
  int channelPermissions = channelOverwritesMePermissions,
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
          sessionProvider.overrideWithValue(
            SessionStore(tokens: channelOverwritesTokens),
          ),
          meProvider.overrideWith((ref) async => channelOverwritesMe),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: MockClient((request) async {
                // Answered here rather than by each test's own handler.
                if (request.method == 'GET' &&
                    request.url.path == '/channels/c1/permissions') {
                  return http.Response(
                    jsonEncode({'permissions': channelPermissions}),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return handler(request);
              }),
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
    await settleUntilFound(tester, find.text('general'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
  });
}
