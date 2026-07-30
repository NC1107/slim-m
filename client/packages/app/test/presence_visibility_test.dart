// SPDX-License-Identifier: Apache-2.0
/// A fresh launch must not claim a presence visibility it cannot read back.
///
/// The preference is durable server-side (`users.presence_visibility`,
/// migration 0008), and no endpoint returns it: `PATCH /presence` echoes only
/// what it just set and `GET /presence` resolves the caller's own id to their
/// true connection state. So the client genuinely does not know, and both the
/// footer line and the menu tick used to assert "online" regardless, telling
/// someone who chose appear-offline that they were visible.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/presence_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/widgets/channel_rail_frame.dart';
import 'package:slimm_app/src/widgets/presence_menu.dart';
import 'package:slimm_app/src/widgets/user_avatar.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Stands in for the real [SyncController], which opens a websocket from its
/// own constructor; overriding `start` keeps it off the network and the
/// assigned state fixes what the footer reads.
class _StubSyncController extends SyncController {
  _StubSyncController(super.ref) {
    state = SyncStatus.live;
  }

  @override
  Future<void> start() async {}
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    syncControllerProvider.overrideWith(_StubSyncController.new),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient((request) async {
          if (request.url.path == '/me') {
            return http.Response(
              jsonEncode({
                'id': 'self',
                'username': 'self',
                'display_name': 'Self',
                'created_at': 0,
                'permissions': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
);

/// `/presence` refuses every request; `/me` still answers so the footer has
/// a caller to render.
ProviderContainer _containerFailingPresence() => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    syncControllerProvider.overrideWith(_StubSyncController.new),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient((request) async {
          if (request.url.path == '/me') {
            return http.Response(
              jsonEncode({
                'id': 'self',
                'username': 'self',
                'display_name': 'Self',
                'created_at': 0,
                'permissions': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/presence') {
            return http.Response(
              '{}',
              500,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
);

Future<void> _pumpFooter(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(
          body: Align(alignment: Alignment.bottomLeft, child: RailUserFooter()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a fresh session starts with no known visibility', () {
    final container = _container();
    addTearDown(container.dispose);

    expect(
      container.read(presenceVisibilityDisplayProvider),
      isNull,
      reason:
          'defaulting to online asserts a stored choice this client has '
          'no endpoint to read back',
    );
  });

  testWidgets('the footer reports the connection rather than claiming online '
      'before any choice is made', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpFooter(tester, container);

    expect(
      find.text('online'),
      findsNothing,
      reason:
          'a user who chose appear-offline last week is still hidden '
          'server-side; telling them they are online is the privacy lie',
    );
    expect(find.text('connected'), findsOneWidget);
  });

  testWidgets('the status menu marks nothing current until a choice is made', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpFooter(tester, container);

    await tester.tap(find.byType(UserAvatar));
    await tester.pumpAndSettle();

    final items = tester.widgetList<AppMenuItem>(
      find.descendant(
        of: find.byType(AppMenu),
        matching: find.byType(AppMenuItem),
      ),
    );
    expect(items, hasLength(presenceOptions.length));
    expect(
      items.where((item) => item.selected),
      isEmpty,
      reason:
          'a tick here reads as "this is your current setting", which '
          'is exactly what this client cannot know',
    );
  });

  testWidgets('a choice made in this session is shown as current', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    container.read(presenceVisibilityDisplayProvider.notifier).state =
        api.PresenceVisibility.hidden;
    await _pumpFooter(tester, container);

    expect(find.text('appear offline'), findsOneWidget);

    await tester.tap(find.byType(UserAvatar));
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<AppMenuItem>(
          find.descendant(
            of: find.byType(AppMenu),
            matching: find.byType(AppMenuItem),
          ),
        )
        .where((item) => item.selected);
    expect(selected.map((item) => item.label), ['Appear offline']);
  });

  testWidgets('a refused change restores the previous choice and shows why, '
      'without closing the menu over it', (tester) async {
    final container = _containerFailingPresence();
    addTearDown(container.dispose);
    container.read(presenceVisibilityDisplayProvider.notifier).state =
        api.PresenceVisibility.away;
    await _pumpFooter(tester, container);

    await tester.tap(find.byType(UserAvatar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appear offline'));
    await tester.pumpAndSettle();

    expect(
      container.read(presenceVisibilityDisplayProvider),
      api.PresenceVisibility.away,
      reason:
          'a refusal must never leave the echo asserting a visibility the '
          'server never applied',
    );
    expect(find.byType(AppErrorState), findsOneWidget);
    // Still open: closing it now would hide the one place showing the error.
    expect(find.byType(AppMenu), findsOneWidget);
  });
}
