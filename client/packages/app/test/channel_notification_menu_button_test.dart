// SPDX-License-Identifier: Apache-2.0
/// The channel header's own route to muting a channel, or narrowing it to
/// mentions only - the same two toggles `channel_row_context_menu_test.dart`
/// and `dm_row_context_menu_test.dart` already cover from the rail's own
/// right-click menu.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/channel_notification_overrides_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/channel_notification_menu_button.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith(
                '/notification-preferences/channels/',
              ) &&
              request.method == 'PUT') {
            final channelId = request.url.pathSegments.last;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'channel_id': channelId,
              'preference': body['preference'],
            });
          }
          return _json(const <Object>[]);
        }),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
);

// Right-aligned, the same reason space_menu_button_test.dart's own harness gives.
Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: ChannelNotificationMenuButton(channelId: 'c1'),
      ),
    ),
  ),
);

void main() {
  testWidgets('opening the menu offers Mute channel and Mentions only', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    await tester.tap(find.byType(ChannelNotificationMenuButton));
    await tester.pumpAndSettle();

    expect(find.text('Mute channel'), findsOneWidget);
    expect(find.text('Mentions only'), findsOneWidget);
    container.dispose();
  });

  testWidgets('tapping Mute channel mutes the channel and closes the menu', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    await tester.tap(find.byType(ChannelNotificationMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute channel'));
    await tester.pumpAndSettle();

    expect(
      container.read(channelNotificationOverridesProvider).overrideFor('c1'),
      api.NotificationPreference.nothing,
    );
    expect(
      find.text('Mute channel'),
      findsNothing,
      reason: 'the menu closes on tap, the same as every other AppMenuItem',
    );
    container.dispose();
  });

  testWidgets('the button icon reflects the muted state once it changes', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(_harness(container));
    await tester.pump();

    expect(find.byIcon(AppIcons.notificationsOn), findsOneWidget);
    expect(find.byIcon(AppIcons.notificationsOff), findsNothing);

    await container
        .read(channelNotificationOverridesProvider.notifier)
        .mute('c1');
    await tester.pump();

    expect(find.byIcon(AppIcons.notificationsOff), findsOneWidget);
    expect(find.byIcon(AppIcons.notificationsOn), findsNothing);
    container.dispose();
  });

  testWidgets('tapping the already-active Mentions only clears the override', (
    tester,
  ) async {
    final container = _container();
    await container
        .read(channelNotificationOverridesProvider.notifier)
        .mentionsOnly('c1');

    await tester.pumpWidget(_harness(container));
    await tester.pump();

    await tester.tap(find.byType(ChannelNotificationMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentions only'));
    await tester.pumpAndSettle();

    expect(
      container.read(channelNotificationOverridesProvider).overrideFor('c1'),
      isNull,
    );
    container.dispose();
  });
}
