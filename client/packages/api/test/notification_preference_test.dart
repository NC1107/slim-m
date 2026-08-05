// SPDX-License-Identifier: Apache-2.0
/// `GET`/`PUT /push/preference`: the caller's own notification preference.
///
/// Its own file rather than a case in `new_routes_test.dart`, which is
/// already at its own allowlisted ceiling; see
/// `presence_visibility_parse_test.dart` for the same reasoning.
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
  test('notificationPreference parses the stored value', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'preference': 'mentions'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    expect(
      await api.notificationPreference(),
      NotificationPreference.mentions,
    );
  });

  test('setNotificationPreference sends the wire name and round-trips it',
      () async {
    Map<String, dynamic>? sentBody;
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'preference': 'nothing'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    final result =
        await api.setNotificationPreference(NotificationPreference.nothing);
    expect(sentBody!['preference'], 'nothing');
    expect(result, NotificationPreference.nothing);
  });

  /// Every recognised value must round-trip, or the tolerant parse below
  /// could be silently answering `everything` for all of them and this
  /// would not know.
  test('every recognised preference reads back as itself', () async {
    for (final preference in NotificationPreference.values) {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'preference': preference.wire}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(api.close);
      expect(await api.notificationPreference(), preference);
    }
  });

  /// The default matches the server's own fallback for a value it cannot
  /// parse (`NotificationPreference::parse` in
  /// `crates/slimm-server/src/notifications.rs`), so client and server never
  /// disagree about what an unrecognised spelling means.
  test('an unrecognised preference reads as everything, not a throw', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'preference': 'occasionally'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    expect(
      await api.notificationPreference(),
      NotificationPreference.everything,
    );
  });

  /// A server too old to have the route answers plain-404, no JSON body: the
  /// signal a caller reads as "not offered here", not as `everything`. See
  /// `client_push.dart`'s own doc comment on `notificationPreference`.
  test('a 404 (a server predating the route) surfaces as NotFoundException',
      () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    expect(
      () => api.notificationPreference(),
      throwsA(isA<NotFoundException>()),
    );
  });
}
