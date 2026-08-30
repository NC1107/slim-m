// SPDX-License-Identifier: Apache-2.0
/// `DELETE /dms/{userId}`: closing a DM out of the caller's own sidebar.
///
/// Its own file, the same split `quiet_hours_test.dart` already uses and
/// explains, rather than growing `new_routes_test.dart` past its allowlisted
/// line count.
library;

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
  test('hideDirectMessage deletes the target user with no body', () async {
    String? path;
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((request) async {
        path = '${request.method} ${request.url.path}';
        return http.Response('', 204);
      }),
    );
    await api.hideDirectMessage('u2');
    expect(path, 'DELETE /dms/u2');
  });
}
