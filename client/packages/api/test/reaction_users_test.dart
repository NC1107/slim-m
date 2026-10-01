// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The who-reacted binding: where it sends, and how it reads a page.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

SlimmApi _api(http.Response Function(http.Request) answer) => SlimmApi(
      baseUrl: Uri.parse('https://chat.example'),
      session: SessionStore(
        tokens: const TokenPair(
          userId: 'u',
          accessToken: 'a',
          refreshToken: 'r',
          accessExpiresAt: 0,
        ),
      ),
      httpClient: MockClient((request) async => answer(request)),
    );

void main() {
  test('asks for one emoji of one message and reads the page', () async {
    late http.Request seen;
    final api = _api((request) {
      seen = request;
      return http.Response(
        jsonEncode({
          'users': [
            {'user_id': 'u1'},
            {'user_id': 'u2'},
          ],
          'next_cursor': '12.u2',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final page = await api.listReactionUsers(
      messageId: 'm1',
      emoji: '\u{1F44D}',
      limit: 2,
      after: '5.u0',
    );

    expect(seen.method, 'GET');
    expect(seen.url.path, startsWith('/messages/m1/reactions/'));
    expect(seen.url.queryParameters, {'limit': '2', 'after': '5.u0'});
    expect(page.userIds, ['u1', 'u2']);
    expect(page.nextCursor, '12.u2');
  });

  test('the last page has no cursor and no query is sent by default', () async {
    late Uri seen;
    final api = _api((request) {
      seen = request.url;
      return http.Response(
        jsonEncode({'users': <Object>[], 'next_cursor': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final page = await api.listReactionUsers(messageId: 'm1', emoji: 'x');

    expect(seen.query, isEmpty);
    expect(page.userIds, isEmpty);
    expect(page.nextCursor, isNull);
  });

  test('a hostile emoji cannot leave the reactions path', () async {
    late Uri seen;
    final api = _api((request) {
      seen = request.url;
      return http.Response(
        jsonEncode({'users': <Object>[], 'next_cursor': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await api.listReactionUsers(messageId: 'm', emoji: '../../account');

    expect(seen.path, startsWith('/messages/m/reactions/'));
  });
}
