// SPDX-License-Identifier: Apache-2.0
/// Tests for `ChannelOrderController`: the order renders the instant a drag
/// completes, and only the round trip decides whether it sticks.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' hide Channel;
import 'package:slimm_app/src/providers/channel_order_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> _channelJson(String id, String name, int position) => {
  'id': id,
  'name': name,
  'kind': 'text',
  'created_at': 0,
  'position': position,
};

ProviderContainer _container(http.Response Function(http.Request) handler) {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
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
        final db = SlimmDatabase(NativeDatabase.memory());
        ref.onDispose(db.close);
        return MessageStore(db);
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the requested order renders before the request answers', () async {
    final container = _container(
      (request) => http.Response(
        jsonEncode([_channelJson('b', 'b', 0), _channelJson('a', 'a', 1)]),
        200,
      ),
    );
    final controller = container.read(channelOrderControllerProvider.notifier);

    final future = controller.reorder(['b', 'a']);
    expect(
      container.read(channelOrderControllerProvider).pendingOrder,
      ['b', 'a'],
      reason:
          'the drag already happened; nothing should wait for the server '
          'to say so before the rail reflects it',
    );

    await future;
    expect(container.read(channelOrderControllerProvider).pendingOrder, null);
    expect(container.read(channelOrderControllerProvider).error, null);
  });

  test(
    'a successful reorder persists the confirmed positions locally',
    () async {
      final container = _container(
        (request) => http.Response(
          jsonEncode([_channelJson('b', 'b', 0), _channelJson('a', 'a', 1)]),
          200,
        ),
      );
      final controller = container.read(
        channelOrderControllerProvider.notifier,
      );

      await controller.reorder(['b', 'a']);

      final store = await container.read(storeProvider.future);
      final rows = await store.allChannels();
      expect(rows.map((c) => c.id), ['b', 'a']);
      expect(rows.map((c) => c.position), [0, 1]);
    },
  );

  test('a refused reorder reverts to nothing pending and shows why', () async {
    final container = _container(
      (request) => http.Response(
        jsonEncode({'error': 'missing live channel(s): c'}),
        400,
      ),
    );
    final controller = container.read(channelOrderControllerProvider.notifier);

    await controller.reorder(['a', 'b']);

    final state = container.read(channelOrderControllerProvider);
    expect(
      state.pendingOrder,
      null,
      reason:
          'a refusal must not leave the rail claiming an order that was '
          'never applied',
    );
    expect(state.error, contains('missing live channel(s): c'));
  });

  test('retry resubmits the same order that last failed', () async {
    var calls = 0;
    final container = _container((request) {
      calls++;
      if (calls == 1) {
        return http.Response(jsonEncode({'error': 'nope'}), 400);
      }
      return http.Response(
        jsonEncode([_channelJson('a', 'a', 0), _channelJson('b', 'b', 1)]),
        200,
      );
    });
    final controller = container.read(channelOrderControllerProvider.notifier);

    await controller.reorder(['a', 'b']);
    expect(container.read(channelOrderControllerProvider).error, isNotNull);

    await controller.retry();
    expect(calls, 2);
    expect(container.read(channelOrderControllerProvider).error, null);
  });

  test('dismiss clears a failure without retrying', () async {
    final container = _container(
      (request) => http.Response(jsonEncode({'error': 'nope'}), 400),
    );
    final controller = container.read(channelOrderControllerProvider.notifier);

    await controller.reorder(['a', 'b']);
    expect(container.read(channelOrderControllerProvider).error, isNotNull);

    controller.dismiss();
    expect(container.read(channelOrderControllerProvider).error, null);
  });
}
