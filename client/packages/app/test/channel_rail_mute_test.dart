// SPDX-License-Identifier: Apache-2.0
/// A muted channel's rail row: the bell-off glyph replaces the unread dot
/// in `AppListRow.trailing`, but `AppListRow.unread` itself - the flag a
/// screen reader and the row's own bold weight both key off - stays exactly
/// what `channel.cursor > channel.lastReadSeq` says regardless of mute.
/// Muting is about interruptions, never about read state; this is what
/// proves the two never share a gate.
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
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

const _tokens = api.TokenPair(
  userId: 'u-me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 4102444800000,
);

Channel _channel(
  String id,
  String name, {
  int cursor = 0,
  int lastReadSeq = 0,
}) => Channel(
  id: id,
  name: name,
  kind: 'text',
  createdAt: 0,
  position: 0,
  cursor: cursor,
  lastReadSeq: lastReadSeq,
  isPersonalSpace: false,
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// Answers the real PUT the mute call sends, so
/// [ChannelNotificationOverridesController.mute] round-trips exactly as it
/// does against the server rather than needing a seam to fake its state.
ProviderContainer _container() => ProviderContainer(
  overrides: [
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

Widget _harness(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('an unmuted channel carries no bell-off glyph', (tester) async {
    final container = _container();
    await tester.pumpWidget(
      _harness(
        container,
        ChannelCategorySections(
          channels: [_channel('c1', 'general')],
          categories: const [],
          selectedId: null,
          onReorder: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(AppIcons.notificationsOff), findsNothing);
    container.dispose();
  });

  testWidgets('muting a channel shows the bell-off glyph on its own row', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(
      _harness(
        container,
        ChannelCategorySections(
          channels: [_channel('c1', 'general')],
          categories: const [],
          selectedId: null,
          onReorder: (_) {},
        ),
      ),
    );
    await tester.pump();

    await container
        .read(channelNotificationOverridesProvider.notifier)
        .mute('c1');
    await tester.pump();

    expect(find.byIcon(AppIcons.notificationsOff), findsOneWidget);
    container.dispose();
  });

  testWidgets(
    'a muted, unread channel still reports itself unread to AppListRow - '
    'muting is about interruptions, not read state',
    (tester) async {
      final container = _container();
      await tester.pumpWidget(
        _harness(
          container,
          ChannelCategorySections(
            channels: [_channel('c1', 'general', cursor: 5, lastReadSeq: 2)],
            categories: const [],
            selectedId: null,
            onReorder: (_) {},
          ),
        ),
      );
      await tester.pump();

      await container
          .read(channelNotificationOverridesProvider.notifier)
          .mute('c1');
      await tester.pump();

      final row = tester.widget<AppListRow>(find.byType(AppListRow));
      expect(
        row.unread,
        isTrue,
        reason:
            'a muted channel with unread messages is still unread; only the '
            'chime and the push are what mute silences',
      );
      expect(row.muted, isTrue);
      container.dispose();
    },
  );

  testWidgets('clearing a mute removes the bell-off glyph again', (
    tester,
  ) async {
    final container = _container();
    await tester.pumpWidget(
      _harness(
        container,
        ChannelCategorySections(
          channels: [_channel('c1', 'general')],
          categories: const [],
          selectedId: null,
          onReorder: (_) {},
        ),
      ),
    );
    await tester.pump();
    final notifier = container.read(
      channelNotificationOverridesProvider.notifier,
    );
    await notifier.mute('c1');
    await tester.pump();
    expect(find.byIcon(AppIcons.notificationsOff), findsOneWidget);

    await notifier.clear('c1');
    await tester.pump();

    expect(find.byIcon(AppIcons.notificationsOff), findsNothing);
    container.dispose();
  });
}
