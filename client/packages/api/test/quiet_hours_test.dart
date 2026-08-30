// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `GET`/`PUT`/`DELETE /push/quiet-hours`: the caller's own quiet-hours
/// window.
///
/// Its own file, the same split `notification_preference_test.dart` already
/// uses and explains.
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
  test('quietHours parses a set window', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'quiet_hours': {'start_minute': 23 * 60, 'end_minute': 8 * 60},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    final window = await api.quietHours();
    expect(window, isNotNull);
    expect(window!.startMinute, 23 * 60);
    expect(window.endMinute, 8 * 60);
  });

  test('quietHours reads a disabled window as null, not an error', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'quiet_hours': null}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    expect(await api.quietHours(), isNull);
  });

  test('setQuietHours sends both minutes and round-trips them', () async {
    Map<String, dynamic>? sentBody;
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          request.body,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    final result = await api.setQuietHours(
      const QuietHours(startMinute: 23 * 60, endMinute: 8 * 60),
    );
    expect(sentBody, {'start_minute': 23 * 60, 'end_minute': 8 * 60});
    expect(result.startMinute, 23 * 60);
    expect(result.endMinute, 8 * 60);
  });

  test('clearQuietHours sends a bare DELETE', () async {
    String? method;
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((request) async {
        method = request.method;
        return http.Response('', 204);
      }),
    );
    addTearDown(api.close);

    await api.clearQuietHours();
    expect(method, 'DELETE');
  });

  /// A server too old to have the route answers plain-404: the same
  /// "not offered here" signal `notification_preference_test.dart` covers
  /// for `GET /push/preference`.
  test('a 404 (a server predating the route) surfaces as NotFoundException',
      () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    expect(() => api.quietHours(), throwsA(isA<NotFoundException>()));
  });
}
