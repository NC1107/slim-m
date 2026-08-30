// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `GET /notification-preferences/channels` and `PUT`/`DELETE
/// .../{channelId}`: a per-channel override of the account-wide preference
/// `notification_preference_test.dart` already covers.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

final _base = Uri.parse('http://localhost:8080');

TokenPair _tokens() => const TokenPair(
      userId: 'u1',
      accessToken: 'access',
      refreshToken: 'refresh',
      accessExpiresAt: 0,
    );

void main() {
  test(
    'listChannelNotificationOverrides parses every entry in the array',
    () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'channel_id': 'c1', 'preference': 'nothing'},
              {'channel_id': 'c2', 'preference': 'mentions'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(api.close);

      final overrides = await api.listChannelNotificationOverrides();
      expect(overrides, hasLength(2));
      expect(overrides[0].channelId, 'c1');
      expect(overrides[0].preference, NotificationPreference.nothing);
      expect(overrides[1].channelId, 'c2');
      expect(overrides[1].preference, NotificationPreference.mentions);
    },
  );

  test('an empty answer parses to an empty list, not a throw', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(const <Object>[]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    expect(await api.listChannelNotificationOverrides(), isEmpty);
  });

  test(
    'setChannelNotificationOverride PUTs to the channel-scoped path and '
    'sends the wire name',
    () async {
      http.Request? sent;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'channel_id': 'c1', 'preference': 'nothing'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);

      final result = await api.setChannelNotificationOverride(
        'c1',
        NotificationPreference.nothing,
      );
      expect(sent!.method, 'PUT');
      expect(sent!.url.path, '/notification-preferences/channels/c1');
      expect(
        (jsonDecode(sent!.body) as Map<String, dynamic>)['preference'],
        'nothing',
      );
      expect(result.channelId, 'c1');
      expect(result.preference, NotificationPreference.nothing);
    },
  );

  test(
    'clearChannelNotificationOverride DELETEs the channel-scoped path',
    () async {
      http.Request? sent;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );
      addTearDown(api.close);

      await api.clearChannelNotificationOverride('c1');
      expect(sent!.method, 'DELETE');
      expect(sent!.url.path, '/notification-preferences/channels/c1');
    },
  );
}
