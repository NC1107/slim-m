// SPDX-License-Identifier: Apache-2.0
/// [voiceRosterProvider]'s polling contract: a text-only deployment stops
/// asking, a transient failure keeps the last known roster rather than
/// clearing it, and an interval governs the real network cost rather than
/// however often something happens to watch it.
library;

import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_roster.dart';

const _tokens = api.TokenPair(
  userId: 'u-me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 4102444800000,
);

ProviderContainer _containerWith(http.Client httpClient) {
  final apiClient = api.SlimmApi(
    baseUrl: Uri.parse('http://localhost:8080'),
    session: api.SessionStore(tokens: _tokens),
    httpClient: httpClient,
  );
  addTearDown(apiClient.close);
  final container = ProviderContainer(
    overrides: [apiProvider.overrideWithValue(apiClient)],
  );
  addTearDown(container.dispose);
  return container;
}

http.Response _roster(List<Map<String, String>> participants) =>
    http.Response(jsonEncode({'participants': participants}), 200);

void main() {
  test('a successful fetch surfaces the roster it was given', () {
    fakeAsync((async) {
      final container = _containerWith(
        MockClient(
          (_) async => _roster([
            {'user_id': 'u1', 'display_name': 'Alice'},
          ]),
        ),
      );
      final sub = container.listen(voiceRosterProvider('general'), (_, __) {});
      async.flushMicrotasks();

      final value = container.read(voiceRosterProvider('general')).value;
      expect(value, hasLength(1));
      expect(value!.single.displayName, 'Alice');
      sub.close();
    });
  });

  test(
    'a deployment with no voice ends the poll instead of retrying forever',
    () {
      fakeAsync((async) {
        var calls = 0;
        final container = _containerWith(
          MockClient((_) async {
            calls++;
            return http.Response('{"error":"no voice"}', 501);
          }),
        );
        final sub = container.listen(
          voiceRosterProvider('general'),
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(calls, 1);
        expect(
          container.read(voiceRosterProvider('general')).isLoading,
          isTrue,
          reason: 'unknown forever, never a false empty list',
        );

        async.elapse(const Duration(hours: 1));
        expect(
          calls,
          1,
          reason: 'a text-only deployment is not worth asking again',
        );
        sub.close();
      });
    },
  );

  test(
    'a transient failure keeps the last known roster rather than clearing it',
    () {
      fakeAsync((async) {
        var calls = 0;
        final container = _containerWith(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return _roster([
                {'user_id': 'u1', 'display_name': 'Alice'},
              ]);
            }
            return http.Response('{"error":"busy"}', 503);
          }),
        );
        final sub = container.listen(
          voiceRosterProvider('general'),
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(
          container
              .read(voiceRosterProvider('general'))
              .value
              ?.single
              .displayName,
          'Alice',
        );

        async.elapse(voiceRosterPollInterval);
        expect(calls, 2, reason: 'the poll retried on schedule');
        expect(
          container
              .read(voiceRosterProvider('general'))
              .value
              ?.single
              .displayName,
          'Alice',
          reason: 'a transient failure must not erase a roster already known',
        );
        sub.close();
      });
    },
  );

  test("a fresh relaunch does not resurrect this client's own stale entry", () {
    fakeAsync((async) {
      final container = _containerWith(
        MockClient(
          (_) async => _roster([
            // What the server still answers moments after a force-quit.
            {'user_id': 'u-me', 'display_name': 'Me'},
            {'user_id': 'u1', 'display_name': 'Alice'},
          ]),
        ),
      );
      final sub = container.listen(voiceRosterProvider('general'), (_, __) {});
      async.flushMicrotasks();

      final value = container.read(voiceRosterProvider('general')).value;
      expect(
        value?.map((p) => p.userId),
        ['u1'],
        reason:
            'a client that never rejoined must not see itself listed as '
            'though it were already in the call',
      );
      sub.close();
    });
  });

  test(
    'the poll interval, not the caller, governs how often the SFU is hit',
    () {
      fakeAsync((async) {
        var calls = 0;
        final container = _containerWith(
          MockClient((_) async {
            calls++;
            return _roster(const []);
          }),
        );
        final sub = container.listen(
          voiceRosterProvider('general'),
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(calls, 1);

        async.elapse(voiceRosterPollInterval * 3);
        expect(calls, 4, reason: 'one fetch plus three ticks of the interval');
        sub.close();
      });
    },
  );
}
